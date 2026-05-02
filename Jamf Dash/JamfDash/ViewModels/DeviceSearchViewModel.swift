import Foundation
import Observation

// MARK: - Action result

enum DeviceActionResult: Equatable {
    case success(String)
    case failure(String)
}

@MainActor
@Observable
final class DeviceSearchViewModel {

    var searchText = ""
    var selectedDevice: Computer? = nil
    private(set) var detailState: LoadState<ComputerDetail> = .idle

    // Action state
    private(set) var isRunningAction = false
    private(set) var runningActionName: String? = nil
    private(set) var lastActionResult: DeviceActionResult? = nil

    private let cli: any CLIRunning
    private let devicesVM: DevicesViewModel

    init(cli: any CLIRunning, devicesVM: DevicesViewModel) {
        self.cli = cli
        self.devicesVM = devicesVM
    }

    // MARK: - Local quick results (from cached device list)

    var localResults: [Computer] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return devicesVM.allComputers.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            ($0.serialNumber?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    // MARK: - Detail fetch

    func selectDevice(_ device: Computer) {
        selectedDevice = device
        guard let serial = device.serialNumber, !serial.isEmpty else {
            // No serial — can't fetch rich detail, build a best-effort detail from what we have
            detailState = .idle
            return
        }
        Task { await fetchDetail(serial: serial) }
    }

    func fetchDetail(serial: String) async {
        detailState = .loading
        do {
            let data = try await cli.run(.computerDetail(serial: serial))
            // jamf-cli may return `null` for not-found
            let trimmed = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "null" || trimmed.isEmpty {
                detailState = .failed("Device not found — verify the serial number and profile permissions.")
                return
            }
            let detail = try JSONDecoder().decode(ComputerDetail.self, from: data)
            detailState = .loaded(detail)
        } catch {
            detailState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Device actions

    /// Execute any device action command. The `name` is shown in the UI while running.
    func runAction(_ command: CLICommand, name: String) async {
        guard !isRunningAction else { return }
        isRunningAction = true
        runningActionName = name
        lastActionResult = nil
        do {
            _ = try await cli.run(command)
            lastActionResult = .success("\(name) completed successfully.")
        } catch {
            lastActionResult = .failure(error.localizedDescription)
        }
        isRunningAction = false
        runningActionName = nil
    }

    func dismissActionResult() {
        lastActionResult = nil
    }

    // MARK: - Navigation

    func clearSelection() {
        selectedDevice = nil
        detailState = .idle
        lastActionResult = nil
    }

    func clearSearch() {
        searchText = ""
        clearSelection()
    }
}

