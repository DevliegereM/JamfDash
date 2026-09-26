import AppKit
import SwiftUI
import XCTest
@testable import JamfDash

/// Renders the Add Connection sheet the way AppKit sizes a sheet (its fitting size) and
/// checks it fits the Settings window. Set TEST_RUNNER_JAMFDASH_SNAPSHOT_DIR to also
/// write PNGs of every variant for a visual check.
@MainActor
final class SettingsLayoutTests: XCTestCase {
    /// Settings window minimum width (SettingsView `.frame(minWidth: 620)`).
    private let maxSheetWidth: CGFloat = 620

    private func makeViewModel() -> SettingsViewModel {
        let keychain = KeychainService()
        let profiles = ProfileService()
        let cli = CLIManager(downloader: CLIDownloader(), profileService: profiles, keychain: keychain, executor: CLIExecutor())
        return SettingsViewModel(keychain: keychain, profileService: profiles, cliManager: cli)
    }

    private func render(_ vm: SettingsViewModel, name: String) -> NSSize {
        let host = NSHostingView(rootView: AddConnectionSheet(vm: vm, isPresented: .constant(true))
            .background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: .darkAqua)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: NSSize(width: size.width, height: min(size.height, 2000)))
        host.layoutSubtreeIfNeeded()
        if let dir = ProcessInfo.processInfo.environment["JAMFDASH_SNAPSHOT_DIR"],
           let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            let url = URL(fileURLWithPath: dir).appendingPathComponent("add-connection-\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        return size
    }

    func testAddConnectionSheetFitsSettingsWindow() {
        let cases: [(String, JamfProduct, SettingsViewModel.SetupMethod?)] = [
            ("pro-platform", .pro, .platform),
            ("pro-local-admin", .pro, .localAccount),
            ("pro-sso", .pro, .sso),
            ("protect", .protect, nil),
            ("school", .school, nil),
        ]
        for (name, product, method) in cases {
            let vm = makeViewModel()
            vm.selectedProduct = product
            if let method { vm.setupMethod = method }
            let size = render(vm, name: name)
            XCTAssertLessThanOrEqual(size.width, maxSheetWidth, "\(name): sheet is \(Int(size.width)) pt wide")
            XCTAssertLessThanOrEqual(size.height, 760, "\(name): sheet is \(Int(size.height)) pt tall")
        }
    }

    // MARK: - DDM Monitor views at a normal window size

    private func snapshot<V: View>(_ view: V, size: NSSize, name: String) -> NSHostingView<some View> {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        if let dir = ProcessInfo.processInfo.environment["JAMFDASH_SNAPSHOT_DIR"],
           let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        return host
    }

    func testDDMStatusItemsViewRenders() {
        let vm = DDMMonitorViewModel(cli: DemoCLIManager())
        _ = snapshot(DDMDeviceStatusTableView(vm: vm), size: NSSize(width: 1000, height: 700), name: "ddm-status-items")
    }

    func testUpdateReadinessViewRenders() async {
        let vm = DDMMonitorViewModel(cli: DemoCLIManager())
        await vm.readiness.load()
        _ = snapshot(UpdateReadinessView(vm: vm.readiness), size: NSSize(width: 1000, height: 700), name: "update-readiness")
    }
}
