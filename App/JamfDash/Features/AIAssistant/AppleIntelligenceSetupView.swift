#if canImport(FoundationModels)
import AppKit
import FoundationModels
import Observation
import SwiftUI

// MARK: - Status

/// Where the on-device model stands, re-checked while a setup screen is visible so the
/// app notices the moment Apple Intelligence is turned on or the model finishes downloading.
@available(macOS 26, *)
@MainActor
@Observable
final class AppleIntelligenceStatus {
    enum State: Equatable {
        case ready
        case notEnabled
        case downloading
        case unsupportedLanguage
        case notEligible
        case unknown
    }

    private(set) var state: State = .unknown
    /// Fixed state for previews and tests; never re-checked.
    private let pinned: Bool

    init() {
        pinned = false
        refresh()
    }

    init(pinnedState: State) {
        pinned = true
        state = pinnedState
    }

    func refresh() {
        guard !pinned else { return }
        state = Self.current()
    }

    static func current() -> State {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale() ? .ready : .unsupportedLanguage
        case .unavailable(.appleIntelligenceNotEnabled): return .notEnabled
        case .unavailable(.modelNotReady):               return .downloading
        case .unavailable(.deviceNotEligible):           return .notEligible
        default:                                         return .unknown
        }
    }

    /// Polls every two seconds until ready or the calling task is cancelled.
    func watch() async {
        while !Task.isCancelled, !pinned {
            refresh()
            if state == .ready { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// System Settings → Apple Intelligence & Siri.
    static func openSettings() {
        let pane = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!
        if !NSWorkspace.shared.open(pane) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
}

// MARK: - Setup guide

/// Step-by-step guide shown instead of Dashie while Apple Intelligence isn't usable.
@available(macOS 26, *)
struct AppleIntelligenceSetupView: View {
    let status: AppleIntelligenceStatus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                switch status.state {
                case .notEnabled:          enableSteps
                case .downloading:         downloading
                case .unsupportedLanguage: languageSteps
                case .notEligible:         notEligible
                case .unknown, .ready:     unknownState
                }
                privacyNote
            }
            .padding(28)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await status.watch() }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: headerSymbol)
                .font(.system(size: 30))
                .foregroundStyle(headerColor)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle).font(.title3.weight(.semibold))
                Text(headerSubtitle)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var enableSteps: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(1, "Open Apple Intelligence & Siri settings",
                 "Use the button below, or choose Apple menu → System Settings → Apple Intelligence & Siri.")
            step(2, "Turn on Apple Intelligence",
                 "Switch on Apple Intelligence and follow the prompts. Your Mac and Siri language must be one Apple Intelligence supports, such as English.")
            step(3, "Let the model download",
                 "macOS downloads the on-device model in the background. Keep the Mac on Wi-Fi and power, with a few gigabytes of free space.")
            HStack(spacing: 12) {
                Button {
                    AppleIntelligenceStatus.openSettings()
                } label: {
                    Label("Open Apple Intelligence Settings", systemImage: "gear")
                }
                .buttonStyle(.borderedProminent)
                checking
            }
            .padding(.top, 4)
        }
    }

    private var downloading: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Downloading the on-device model…").font(.subheadline.weight(.medium))
            }
            Text("This happens once and can take a while. Keep your Mac connected to Wi-Fi and power, with a few gigabytes of free space. Dashie opens by itself when it's done.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Apple Intelligence Settings") { AppleIntelligenceStatus.openSettings() }
                .buttonStyle(.bordered)
        }
    }

    private var languageSteps: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(1, "Check your languages",
                 "Apple Intelligence works in a set of supported languages. Set the Mac language (System Settings → General → Language & Region) and the Siri language (Apple Intelligence & Siri) to a supported one, such as English.")
            step(2, "Wait for the model",
                 "After changing the language, macOS may download the model for that language.")
            HStack(spacing: 12) {
                Button("Open Apple Intelligence Settings") { AppleIntelligenceStatus.openSettings() }
                    .buttonStyle(.borderedProminent)
                checking
            }
        }
    }

    private var notEligible: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apple Intelligence needs a Mac with Apple silicon (M1 or later). This Mac can't run the on-device model, so Dashie and plain-language device search aren't available.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Everything else in Jamf Dash works as usual.")
                .font(.subheadline)
        }
    }

    private var unknownState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("macOS reports Apple Intelligence as unavailable without saying why. Check System Settings → Apple Intelligence & Siri.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Open Apple Intelligence Settings") { AppleIntelligenceStatus.openSettings() }
                    .buttonStyle(.bordered)
                checking
            }
        }
    }

    private var privacyNote: some View {
        Label("Dashie only uses Apple's on-device model. Your fleet data never leaves this Mac.",
              systemImage: "lock.shield")
            .font(.caption).foregroundStyle(.secondary)
            .padding(.top, 6)
    }

    private var checking: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text("Checking automatically…").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title). \(detail)")
    }

    // MARK: Header content

    private var headerTitle: String {
        switch status.state {
        case .notEnabled:          return "Turn on Apple Intelligence to use Dashie"
        case .downloading:         return "Almost there"
        case .unsupportedLanguage: return "Apple Intelligence doesn't support this language yet"
        case .notEligible:         return "This Mac can't run Apple Intelligence"
        case .unknown, .ready:     return "Apple Intelligence isn't available"
        }
    }

    private var headerSubtitle: String {
        switch status.state {
        case .notEnabled:
            return "Dashie runs on Apple's on-device model. It takes a minute to set up, and Dashie starts as soon as it's ready."
        case .downloading:
            return "Apple Intelligence is on; macOS is still downloading the model."
        case .unsupportedLanguage:
            return "The model is installed, but not for your current language."
        case .notEligible:
            return "Dashie needs Apple's on-device model."
        case .unknown, .ready:
            return "Dashie needs Apple's on-device model."
        }
    }

    private var headerSymbol: String {
        switch status.state {
        case .downloading: return "arrow.down.circle"
        case .notEligible: return "xmark.octagon"
        default:           return "apple.intelligence"
        }
    }

    private var headerColor: Color {
        switch status.state {
        case .notEligible: return .secondary
        case .downloading: return .blue
        default:           return .purple
        }
    }
}
#endif
