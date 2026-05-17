import SwiftUI
import AppKit
import Sparkle

@main
struct JamfDashApp: App {
    @State private var env = AppEnvironment()
    @State private var appState: AppState

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        let env = AppEnvironment()
        self._env = State(initialValue: env)
        self._appState = State(initialValue: AppState(env: env))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(env)
                .task { await appState.bootstrap() }
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
                ForEach(1...9, id: \.self) { index in
                    Button("Item \(index)") {
                        NotificationCenter.default.post(
                            name: .navigateToSidebarItem,
                            object: nil,
                            userInfo: ["index": index - 1]
                        )
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: .command)
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

        Window("Jamf Dash Help", id: "jamf-help") {
            HelpView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 680, height: 620)
    }
}
