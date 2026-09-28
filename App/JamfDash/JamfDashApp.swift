import AppKit
import OSLog
import Sparkle
import SwiftUI
import UserNotifications

private let appLogger = Logger(subsystem: "com.jamfdash", category: "App")

@main
struct JamfDashApp: App {
    @State private var env: AppEnvironment
    @State private var appState: AppState

    /// True when XCTest launched the app to host the unit tests.
    static let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        // A jamf-cli that exits before reading stdin must not kill the app.
        signal(SIGPIPE, SIG_IGN)
        // Apply debug logging before ANY other initialisation so that the very
        // first log message in this init() is already captured at debug level.
        // Supports three activation paths:
        //   1. Previously enabled via Settings (plist already on disk).
        //   2. --debug launch argument: open -a "JamfDash" --args --debug
        //   3. Manually installed plist (see Developer tab for the Terminal command).
        // --debug is a developer convenience and does not bypass any security
        // boundary — it only routes OSLog output to disk, which an attacker who
        // can control launch arguments already has access to.
        if CommandLine.arguments.contains("--debug") {
            DebugLoggingService.shared.isEnabled = true
        }
        DebugLoggingService.shared.applyOnLaunch()
        appLogger.info("JamfDash launching (debug logging: \(DebugLoggingService.shared.isEnabled, privacy: .public))")
        NSWindow.allowsAutomaticWindowTabbing = false
        // As the unit tests' host the app must not sync a real Jamf instance or write to its
        // data folder: it starts with the demo environment and skips startup.
        let env = Self.isTestHost ? AppEnvironment.demo() : AppEnvironment()
        self._env = State(initialValue: env)
        self._appState = State(initialValue: AppState(env: env))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(env)
                .task {
                    guard !Self.isTestHost else { return }
                    await appState.bootstrap()
                }
                .task {
                    guard !Self.isTestHost else { return }
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound])
                }
                .onChange(of: appState.demoModeRequested) { _, requested in
                    guard requested else { return }
                    let demoEnv = AppEnvironment.demo()
                    env = demoEnv
                    appState.activateDemoMode(demoEnv: demoEnv)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Jamf Dash Help") {
                    NotificationCenter.default.post(name: .openHelpWindow, object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
                Divider()
                Button("Report a Problem…") {
                    ReportProblem.open()
                }
            }

            CommandGroup(after: .appVisibility) {
                Button("Refresh") {
                    NotificationCenter.default.post(name: .refreshCurrentView, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Device Search") {
                    NotificationCenter.default.post(name: .openDeviceSearch, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Focus Search") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            CommandMenu("Navigate") {
                let items = Array(SidebarItem.items(for: env.currentProduct).prefix(9).enumerated())
                ForEach(items, id: \.offset) { index, item in
                    Button(item.title) {
                        NotificationCenter.default.post(
                            name: .navigateToSidebarItem,
                            object: nil,
                            userInfo: ["index": index]
                        )
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }

            CommandGroup(after: .appInfo) {
                Button("Check for App Updates…") {
                    AppUpdater.shared.checkForUpdates()
                }
                Divider()
                Button("Check for CLI Updates…") {
                    Task { @MainActor in
                        do {
                            if let newVersion = try await appState.checkForCLIUpdate() {
                                let alert = NSAlert()
                                alert.messageText = "Update Available: jamf-cli \(newVersion)"
                                alert.informativeText = "Click \"Update Now\" in the banner at the top of the window, or go to Settings → CLI to update."
                                alert.addButton(withTitle: "OK")
                                alert.runModal()
                            } else {
                                let installed = await appState.installedCLIVersion ?? "unknown"
                                let alert = NSAlert()
                                alert.messageText = "jamf-cli is up to date"
                                alert.informativeText = "Installed version: \(installed)"
                                alert.addButton(withTitle: "OK")
                                alert.runModal()
                            }
                        } catch {
                            let alert = NSAlert()
                            alert.messageText = "Update Check Failed"
                            alert.informativeText = error.localizedDescription
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                        }
                    }
                }
            }
        }

        Settings {
            SettingsView(vm: env.makeSettingsVM())
                .environment(env)
                .environment(appState)
                .frame(minWidth: 620, minHeight: 520)
        }

        Window("Report a Problem", id: "report-problem") {
            ReportProblemView()
                .environment(env)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 760, height: 640)
        .windowResizability(.contentMinSize)

        Window("Jamf Dash Help", id: "jamf-help") {
            HelpView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 980, height: 680)
    }
}
