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

    private(set) var complianceBenchmarksState: LoadState<[JamfComplianceBenchmark]> = .idle
    private(set) var benchmarkDetailState: LoadState<BenchmarkDetailResult> = .idle
    var selectedBenchmarkID: String? = nil

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
        } catch {
            Self.logger.error("Failed to load blueprints: \(error)")
            blueprintsState = .failed(ErrorMessageFormatter.message(for: error))
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
