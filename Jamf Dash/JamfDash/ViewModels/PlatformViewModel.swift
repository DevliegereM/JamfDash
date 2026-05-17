import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class PlatformViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "PlatformViewModel")

    // MARK: - Properties

    private(set) var blueprintsState: LoadState<[JamfBlueprint]> = .idle
    private(set) var blueprintDetailState: LoadState<String> = .idle
    var selectedBlueprintID: String? = nil

    private(set) var complianceBenchmarksState: LoadState<[JamfComplianceBenchmark]> = .idle
    private(set) var benchmarkDetailState: LoadState<String> = .idle
    private(set) var benchmarkResultsState: LoadState<String> = .idle
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
            blueprintDetailState = .loaded(Self.prettyPrint(data))
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
            let benchmarks: [JamfComplianceBenchmark]
            if let direct = try? JSONDecoder().decode([JamfComplianceBenchmark].self, from: data) {
                benchmarks = direct
            } else if let wrapped = try? JSONDecoder().decode(JamfComplianceBenchmarkListResponse.self, from: data) {
                benchmarks = wrapped.results ?? []
            } else {
                benchmarks = []
            }
            complianceBenchmarksState = .loaded(benchmarks)
        } catch {
            Self.logger.error("Failed to load compliance benchmarks: \(error)")
            complianceBenchmarksState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadBenchmarkDetail(name: String) async {
        benchmarkDetailState = .loading
        do {
            let data = try await cli.run(.complianceBenchmarkDetail(name: name))
            benchmarkDetailState = .loaded(Self.prettyPrint(data))
        } catch {
            benchmarkDetailState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadBenchmarkResults(name: String) async {
        benchmarkResultsState = .loading
        do {
            let data = try await cli.run(.complianceBenchmarkResults(name: name))
            benchmarkResultsState = .loaded(Self.prettyPrint(data))
        } catch {
            benchmarkResultsState = .failed(ErrorMessageFormatter.message(for: error))
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
