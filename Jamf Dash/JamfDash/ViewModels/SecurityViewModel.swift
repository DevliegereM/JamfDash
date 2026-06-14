import Foundation
import OSLog
import Observation

// MARK: - Patch Status Item

private struct PatchStatusItem: Decodable, Sendable {
    /// The patch/installation status string. Optional so missing keys don't crash decoding.
    let status: String?

    private enum CodingKeys: String, CodingKey {
        // jamf-cli varies the field name across versions and report types
        case status
        case patchStatus, patch_status
        case installationStatus, installation_status, installedStatus, installed_status
        case deploymentStatus, deployment_status
        case state, complianceState, compliance_state
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var raw = (try? c.decode(String.self, forKey: .status))
        if raw == nil { raw = (try? c.decode(String.self, forKey: .patchStatus))
                             ?? (try? c.decode(String.self, forKey: .patch_status)) }
        if raw == nil { raw = (try? c.decode(String.self, forKey: .installationStatus))
                             ?? (try? c.decode(String.self, forKey: .installation_status)) }
        if raw == nil { raw = (try? c.decode(String.self, forKey: .installedStatus))
                             ?? (try? c.decode(String.self, forKey: .installed_status)) }
        if raw == nil { raw = (try? c.decode(String.self, forKey: .deploymentStatus))
                             ?? (try? c.decode(String.self, forKey: .deployment_status)) }
        if raw == nil { raw = (try? c.decode(String.self, forKey: .state))
                             ?? (try? c.decode(String.self, forKey: .complianceState))
                             ?? (try? c.decode(String.self, forKey: .compliance_state)) }
        status = raw?.isEmpty == false ? raw : nil
    }

    /// True when the status value indicates the patch has been successfully applied.
    var isCompliant: Bool {
        guard let s = status?.lowercased() else { return false }
        return s == "completed"
            || s == "installed"
            || s == "up to date"
            || s == "uptodate"
            || s == "current"
            || s == "compliant"
            || s == "success"
            || s == "ok"
    }
}

// MARK: - SecurityViewModel

@MainActor
@Observable
final class SecurityViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "SecurityViewModel")

    // MARK: - Properties

    private(set) var state: LoadState<SecurityReport> = .idle
    private(set) var patchCompliancePct: Double? = nil

    private let repository: SecurityRepository
    // NOTE: AppEnvironment.swift must be updated to pass `cli:` to SecurityViewModel.
    // Both the live init and the demo init call `SecurityViewModel(repository: securityRepo)`;
    // they should be changed to `SecurityViewModel(repository: securityRepo, cli: <cliManager>)`.
    private let cli: any CLIRunning

    private var isPatchLoading = false

    // MARK: - Initialization

    init(repository: SecurityRepository, cli: any CLIRunning) {
        self.repository = repository
        self.cli = cli
    }

    // MARK: - Public Methods

    func load(force: Bool = false) async {
        guard force || state.value == nil else { return }
        guard force || !state.isLoading else { return }
        Self.logger.debug("Loading security report")
        state = .loading
        do {
            let report = try await repository.fetch()
            Self.logger.debug("Loaded security report: \(report.devices.count) devices")
            state = .loaded(report)
        } catch {
            Self.logger.error("Failed to load security report: \(error)")
            state = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadPatchCompliance(force: Bool = false) async {
        guard force || patchCompliancePct == nil else { return }
        guard !isPatchLoading else { return }
        isPatchLoading = true
        defer { isPatchLoading = false }

        Self.logger.debug("Loading patch compliance")
        do {
            let data  = try await cli.run(.reportPatchStatus)
            let items = Self.decodePatchItems(from: data)
            guard !items.isEmpty else {
                Self.logger.warning("Patch status report is empty — skipping compliance calculation")
                patchCompliancePct = nil
                return
            }
            let itemsWithStatus = items.filter { $0.status != nil }
            if itemsWithStatus.isEmpty {
                Self.logger.warning("Patch status report has \(items.count) item(s) but none contain a recognisable status field — score will remain partial")
                patchCompliancePct = nil
                return
            }
            let compliantCount = itemsWithStatus.filter(\.isCompliant).count
            patchCompliancePct = Double(compliantCount) / Double(itemsWithStatus.count) * 100
            Self.logger.info("Patch compliance: \(self.patchCompliancePct ?? 0, privacy: .public)% (\(compliantCount)/\(itemsWithStatus.count) compliant)")
        } catch {
            Self.logger.warning("Failed to load patch compliance: \(error) — score will remain partial")
            patchCompliancePct = nil
        }
    }

    /// Decodes a flat or wrapped patch status array, never throwing.
    private static func decodePatchItems(from data: Data) -> [PatchStatusItem] {
        let decoder = JSONDecoder()
        // Try flat array first
        if let items = try? decoder.decode([PatchStatusItem].self, from: data) { return items }
        // Try common wrapper keys
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["results", "items", "data", "patchItems", "patch_items", "records"] {
                if let arr = obj[key],
                   let arrData = try? JSONSerialization.data(withJSONObject: arr),
                   let items = try? decoder.decode([PatchStatusItem].self, from: arrData) {
                    return items
                }
            }
        }
        return []
    }

    // MARK: - Computed Properties

    var summary: SecuritySummary? { state.value?.summary }
    var osVersions: [OSVersionRow] { state.value?.osVersions ?? [] }
    var devices: [DeviceSecurity] { state.value?.devices ?? [] }
}
