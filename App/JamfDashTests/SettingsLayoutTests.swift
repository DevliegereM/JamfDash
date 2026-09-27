import AppKit
import SwiftUI
import XCTest
import FoundationModels
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

    @available(macOS 26, *)
    func testAppleIntelligenceSetupStatesRender() {
        let states: [(AppleIntelligenceStatus.State, String)] = [
            (.notEnabled, "ai-setup-not-enabled"), (.downloading, "ai-setup-downloading"),
            (.unsupportedLanguage, "ai-setup-language"), (.notEligible, "ai-setup-not-eligible"),
        ]
        for (state, name) in states {
            let host = snapshot(AppleIntelligenceSetupView(status: AppleIntelligenceStatus(pinnedState: state)),
                                size: NSSize(width: 900, height: 620), name: name)
            XCTAssertLessThanOrEqual(host.fittingSize.width, 900, "\(name) wider than the window")
        }
    }

    @available(macOS 26, *)
    func testLocaleProbe() {
        let model = SystemLanguageModel.default
        print("LOCALE current=\(Locale.current.identifier) preferred=\(Locale.preferredLanguages) supportsCurrent=\(model.supportsLocale()) state=\(AppleIntelligenceStatus.current())")
    }

    func testHelpWindowRenders() {
        _ = snapshot(HelpView(), size: NSSize(width: 980, height: 680), name: "help-window")
        let topic = HelpLibrary.topic(id: "platform-api")!
        _ = snapshot(HelpTopicView(topic: topic) { _ in }, size: NSSize(width: 700, height: 680), name: "help-topic-steps")
        let shortcuts = HelpLibrary.topic(id: "shortcuts")!
        _ = snapshot(HelpTopicView(topic: shortcuts) { _ in }, size: NSSize(width: 700, height: 500), name: "help-topic-shortcuts")
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

    // MARK: - Minimum size: a view's minimum size is what a window is forced to grow to

    private func minimumSize<V: View>(_ view: V) -> NSSize {
        let host = NSHostingView(rootView: view)
        return host.fittingSize
    }

    func testDDMViewsDoNotForceTallWindows() async {
        let vm = DDMMonitorViewModel(cli: DemoCLIManager())
        await vm.readiness.load()
        await vm.loadFleetStatus()
        await vm.load()
        let readiness = minimumSize(UpdateReadinessView(vm: vm.readiness))
        let status = minimumSize(DDMDeviceStatusTableView(vm: vm))
        let fleet = minimumSize(DDMFleetStatusView(vm: vm))
        print("MINSIZE readiness=\(readiness) status=\(status) fleet=\(fleet)")
        XCTAssertLessThanOrEqual(readiness.height, 500, "Update Readiness forces a \(Int(readiness.height)) pt tall window")
        XCTAssertLessThanOrEqual(status.height, 500)
        XCTAssertLessThanOrEqual(fleet.height, 500)
    }

    func testDDMFleetOverviewRenders() async {
        let vm = DDMMonitorViewModel(cli: DemoCLIManager())
        await vm.loadFleetStatus()
        await vm.load()
        _ = snapshot(DDMFleetStatusView(vm: vm), size: NSSize(width: 1000, height: 700), name: "ddm-fleet-overview")
    }

    // MARK: - Real window sizing

    /// Puts the view in an off-screen window at 1000×700 and returns the window's content
    /// size and minimum size after SwiftUI has laid it out.
    private func windowSizes<V: View>(_ view: V) -> (content: NSSize, min: NSSize) {
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.layoutIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        return (window.contentLayoutRect.size, window.contentMinSize)
    }

    func testUpdateReadinessKeepsWindowSize() async {
        let vm = DDMMonitorViewModel(cli: DemoCLIManager())
        await vm.readiness.load()
        vm.readiness.filter = .all
        let sizes = windowSizes(UpdateReadinessView(vm: vm.readiness))
        print("WINDOW readiness content=\(sizes.content) min=\(sizes.min) rows=\(vm.readiness.filteredRows.count)")
        XCTAssertLessThanOrEqual(sizes.content.height, 700, "Update Readiness grew the window to \(Int(sizes.content.height)) pt")
        XCTAssertLessThanOrEqual(sizes.min.height, 500)
    }

    func testDDMMonitorViewsKeepWindowSize() async {
        let vm = DDMMonitorViewModel(cli: DemoCLIManager())
        await vm.load()
        await vm.loadFleetStatus()
        await vm.readiness.load()
        let cases: [(String, AnyView)] = [
            ("monitor", AnyView(DDMMonitorView(vm: vm))),
            ("status-items", AnyView(DDMDeviceStatusTableView(vm: vm))),
            ("fleet", AnyView(DDMFleetStatusView(vm: vm))),
        ]
        for (name, view) in cases {
            let sizes = windowSizes(view)
            print("WINDOW \(name) content=\(sizes.content) min=\(sizes.min)")
            XCTAssertLessThanOrEqual(sizes.min.height, 500, "\(name) forces a \(Int(sizes.min.height)) pt tall window")
            XCTAssertLessThanOrEqual(sizes.min.width, 1000, "\(name) forces a \(Int(sizes.min.width)) pt wide window")
        }
    }
}
