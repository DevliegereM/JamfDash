import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class PlatformViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "PlatformViewModel")

    // MARK: - Properties

    private(set) var blueprintsState: LoadState<[JamfBlueprint]> = .idle
    private(set) var blueprintDetailState: LoadState<BlueprintDetailResult> = .idle
    var selectedBlueprintID: String? = nil
    /// Deployment counts per blueprint name; empty when the report is unavailable.
    private(set) var blueprintStatuses: [String: BlueprintStatus] = [:]

    private(set) var complianceBenchmarksState: LoadState<[JamfComplianceBenchmark]> = .idle
    private(set) var benchmarkDetailState: LoadState<BenchmarkDetailResult> = .idle
    var selectedBenchmarkID: String? = nil

    /// Compliance results for the selected benchmark (Platform benchmark reports).
    private(set) var benchmarkResultsState: LoadState<BenchmarkResults> = .idle
    private(set) var failingDevicesState: LoadState<[BenchmarkDeviceCompliance]> = .idle
    /// Failing devices per rule ID, loaded when a rule is expanded.
    private(set) var ruleDevices: [String: LoadState<[BenchmarkRuleDevice]>] = [:]

    private let cli: any CLIRunning

    // MARK: - Initialization

    init(cli: any CLIRunning) {
        self.cli = cli
    }

    // MARK: - Public Methods

    func loadBlueprints(force: Bool = false) async {
        guard force || blueprintsState.value == nil else { return }
        guard force || !blueprintsState.isLoading else { return }
        blueprintsState = .loading
        do {
            let data = try await cli.run(.blueprints)
            let blueprints: [JamfBlueprint]
            if let direct = try? JSONDecoder().decode([JamfBlueprint].self, from: data) {
                blueprints = direct
            } else if let wrapped = try? JSONDecoder().decode(JamfBlueprintListResponse.self, from: data) {
                blueprints = wrapped.results ?? []
            } else {
                blueprints = []
            }
            blueprintsState = .loaded(blueprints)
            await loadBlueprintStatuses()
        } catch {
            Self.logger.error("Failed to load blueprints: \(error)")
            blueprintsState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    /// Optional extra: the list works without it, so failures are only logged.
    func loadBlueprintStatuses() async {
        do {
            blueprintStatuses = BlueprintStatus.byName(try await cli.run(.blueprintStatus))
        } catch {
            Self.logger.error("Blueprint status report unavailable: \(error.localizedDescription, privacy: .public)")
            blueprintStatuses = [:]
        }
    }

    func loadBlueprintDetail(name: String) async {
        blueprintDetailState = .loading
        do {
            let data = try await cli.run(.blueprintDetail(name: name))
            let rawJSON = Self.prettyPrint(data)
            let detail = try? makeBlueprintDecoder().decode(BlueprintDetail.self, from: data)
            blueprintDetailState = .loaded(BlueprintDetailResult(detail: detail, rawJSON: rawJSON))
        } catch {
            blueprintDetailState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadComplianceBenchmarks(force: Bool = false) async {
        guard force || complianceBenchmarksState.value == nil else { return }
        guard force || !complianceBenchmarksState.isLoading else { return }
        complianceBenchmarksState = .loading
        do {
            let data = try await cli.run(.complianceBenchmarks)
            let benchmarks = try Self.decodeComplianceBenchmarks(from: data)
            complianceBenchmarksState = .loaded(benchmarks)
        } catch {
            Self.logger.error("Failed to load compliance benchmarks: \(error)")
            complianceBenchmarksState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    private static func decodeComplianceBenchmarks(from data: Data) throws -> [JamfComplianceBenchmark] {
        let snakeDecoder: JSONDecoder = {
            let d = JSONDecoder()
            d.keyDecodingStrategy = .convertFromSnakeCase
            return d
        }()

        // 1. Direct array – camelCase
        if let direct = try? JSONDecoder().decode([JamfComplianceBenchmark].self, from: data) {
            return direct
        }
        // 2. Direct array – snake_case keys
        if let direct = try? snakeDecoder.decode([JamfComplianceBenchmark].self, from: data) {
            return direct
        }
        // 3. Wrapped object – camelCase
        if let wrapped = try? JSONDecoder().decode(JamfComplianceBenchmarkListResponse.self, from: data) {
            return wrapped.resolved
        }
        // 4. Wrapped object – snake_case keys
        if let wrapped = try? snakeDecoder.decode(JamfComplianceBenchmarkListResponse.self, from: data) {
            return wrapped.resolved
        }

        // None of the known shapes matched; log the raw payload for diagnosis.
        let preview = String(data: data.prefix(500), encoding: .utf8) ?? "<non-UTF8>"
        Self.logger.error("Unable to decode compliance benchmarks. Raw preview: \(preview)")
        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unknown compliance benchmarks response shape"))
    }

    /// Loads the compliance results for a benchmark. `title` is needed for the per-device
    /// report, which only accepts the benchmark title.
    func loadBenchmarkResults(id: String) async {
        benchmarkResultsState = .loading
        failingDevicesState = .idle
        ruleDevices = [:]
        let title = complianceBenchmarksState.value?.first { $0.id == id }?.name

        async let percentData = try? cli.run(.benchmarkCompliancePercentage(id: id))
        let rulesResult: Result<Data, Error>
        do { rulesResult = .success(try await cli.run(.benchmarkRuleStats(id: id))) }
        catch { rulesResult = .failure(error) }
        let percent = await percentData.flatMap(Self.compliancePercentage)
        guard selectedBenchmarkID == id else { return }

        switch rulesResult {
        case .success(let data):
            guard let rules = BenchmarkRuleStat.decodeList(data) else {
                benchmarkResultsState = .failed("The benchmark report couldn't be read.")
                return
            }
            benchmarkResultsState = .loaded(BenchmarkResults(compliancePercentage: percent, rules: rules))
        case .failure(let error):
            Self.logger.error("Benchmark report failed: \(error.localizedDescription, privacy: .public)")
            benchmarkResultsState = .failed(ErrorMessageFormatter.message(for: error))
            return
        }

        guard let title else { return }
        failingDevicesState = .loading
        do {
            let data = try await cli.run(.benchmarkFailingDevices(title: title))
            guard selectedBenchmarkID == id else { return }
            let devices = (try? JSONDecoder().decode([BenchmarkDeviceCompliance].self, from: data)) ?? []
            failingDevicesState = .loaded(devices)
        } catch {
            guard selectedBenchmarkID == id else { return }
            failingDevicesState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadRuleDevices(benchmarkID: String, ruleID: String) async {
        if case .loaded = ruleDevices[ruleID] { return }
        if ruleDevices[ruleID]?.isLoading == true { return }
        ruleDevices[ruleID] = .loading
        do {
            let data = try await cli.run(.benchmarkRuleDevices(id: benchmarkID, ruleID: ruleID))
            guard selectedBenchmarkID == benchmarkID else { return }
            if let devices = BenchmarkRuleDevice.decodeList(data) {
                ruleDevices[ruleID] = .loaded(devices)
            } else {
                ruleDevices[ruleID] = .failed("The device list couldn't be read.")
            }
        } catch {
            guard selectedBenchmarkID == benchmarkID else { return }
            ruleDevices[ruleID] = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    nonisolated static func compliancePercentage(_ data: Data) -> Double? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let d = obj["compliancePercentage"] as? Double { return d }
        if let n = obj["compliancePercentage"] as? NSNumber { return n.doubleValue }
        return nil
    }

    func loadBenchmarkDetail(name: String) async {
        benchmarkDetailState = .loading
        do {
            let data = try await cli.run(.complianceBenchmarkDetail(name: name))
            let rawJSON = Self.prettyPrint(data)
            let detail = try? makeBenchmarkDecoder().decode(BenchmarkDetail.self, from: data)
            benchmarkDetailState = .loaded(BenchmarkDetailResult(detail: detail, rawJSON: rawJSON))
        } catch {
            benchmarkDetailState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    // MARK: - Error Classification

    static func isPlatformAuthError(_ message: String) -> Bool {
        message.contains("platform gateway auth")
    }

    // MARK: - Private Methods

    private static func prettyPrint(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let str = String(data: pretty, encoding: .utf8) else {
            return String(data: data, encoding: .utf8) ?? "Unable to decode response"
        }
        return str
    }
}
