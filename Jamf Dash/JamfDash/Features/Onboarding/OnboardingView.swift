import SwiftUI

struct OnboardingView: View {
    @Bindable var vm: OnboardingViewModel
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots: welcome · install · product · done
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(stepIndex >= i ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 32)

            Divider().padding(.top, 16)

            Group {
                switch vm.step {
                case .welcome:       WelcomeStep(vm: vm)
                case .cliSetup:      CLISetupStep(vm: vm)
                case .productPicker: ProductPickerStep(vm: vm)
                case .authMethod:    AuthMethodStep(vm: vm)
                case .proSetup:      LocalSetupStep(vm: vm)
                case .ssoSetup:      SSOSetupStep(vm: vm)
                case .protectSetup:  ProtectSetupStep(vm: vm)
                case .schoolSetup:   SchoolSetupStep(vm: vm)
                case .complete:      CompleteStep(product: vm.selectedProduct, onComplete: onComplete)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.easeInOut(duration: 0.3), value: vm.step)
        }
        .frame(width: 540, height: 560)
    }

    private var stepIndex: Int {
        switch vm.step {
        case .welcome:                                   return 0
        case .cliSetup:                                  return 1
        case .productPicker:                             return 2
        case .authMethod, .proSetup, .ssoSetup,
             .protectSetup, .schoolSetup:                return 3
        case .complete:                                  return 3
        }
    }
}

// MARK: - Welcome

private struct WelcomeStep: View {
    let vm: OnboardingViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 24)

            Text("Welcome to Jamf Dash")
                .font(.title).bold()

            Text("A native macOS dashboard for your Jamf environment.\n\nJamf Dash uses **jamf-cli** to connect to your server. We'll download it and guide you through the connection setup.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            Spacer()

            Button("Get Started") { vm.advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            Button("Try Demo") {
                appState.requestDemoMode()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - CLI Download

private struct CLISetupStep: View {
    let vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
                .padding(.top, 24)

            Text("Install jamf-cli")
                .font(.title2).bold()

            Text("Jamf Dash uses the official **jamf-cli** binary from Jamf Concepts. It will be downloaded automatically, or check if it's already installed.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            Link("Jamf Concepts / jamf-cli on GitHub ↗", destination: URL(string: "https://github.com/Jamf-Concepts/jamf-cli")!)
                .font(.caption)

            if vm.isDownloading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(vm.downloadProgress).font(.caption).foregroundStyle(.secondary)
                }
            } else if !vm.downloadProgress.isEmpty {
                Label(vm.downloadProgress, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            if let error = vm.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).font(.caption)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
            }

            Spacer()

            Button(vm.isDownloading ? "Checking…" : "Check & Install") {
                Task { await vm.downloadCLI() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(vm.isDownloading)

            Button("Skip — I'll install it manually") {
                vm.skipCLISetup()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Product Picker

private struct ProductPickerStep: View {
    let vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.grid.3x1.fill.below.line.grid.1x2")
                .font(.system(size: 50))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 24)

            Text("Which Jamf product are you connecting to?")
                .font(.title2).bold()
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                ForEach(JamfProduct.allCases, id: \.self) { product in
                    ProductCard(product: product) {
                        vm.chooseProduct(product)
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

private struct ProductCard: View {
    let product: JamfProduct
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: product.icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName).fontWeight(.semibold)
                    Text(product.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Auth Method Choice (Pro only)

private struct AuthMethodStep: View {
    let vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 24)

            Text("How does your Jamf Pro authenticate?")
                .font(.title2).bold()
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                AuthMethodCard(
                    title: "Local Admin Account",
                    description: "Your Jamf Pro instance has local admin accounts enabled. Jamf Dash will automatically create a dedicated API client for you.",
                    icon: "person.fill.checkmark",
                    action: { vm.chooseAuthMethod(.localAccount) }
                )

                AuthMethodCard(
                    title: "SSO / No Local Accounts",
                    description: "Your instance uses SSO or has local admin accounts disabled. You'll create an API client manually in Jamf Pro and paste the credentials here.",
                    icon: "building.2.fill",
                    action: { vm.chooseAuthMethod(.sso) }
                )
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

private struct AuthMethodCard: View {
    let title: String
    let description: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title).fontWeight(.semibold)
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pro Local Account Setup

private struct LocalSetupStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Image(systemName: "person.fill.checkmark")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 16)
                    Text("Local Admin Setup")
                        .font(.title2).bold()
                    Text("Enter your Jamf Pro admin credentials. Jamf Dash will create a dedicated API client and store it securely.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 400)
                }

                formRows {
                    row("Server URL") {
                        TextField("https://yourinstance.jamfcloud.com", text: $vm.serverURL)
                    }
                    row("Username") {
                        TextField("Admin username", text: $vm.username)
                            .textContentType(.username)
                    }
                    row("Password") {
                        SecureField("Password", text: $vm.password)
                            .textContentType(.password)
                    }
                    row("API Scope") {
                        Picker("", selection: $vm.scope) {
                            ForEach(OnboardingViewModel.APIScope.allCases) { s in
                                Text(s.label).tag(s)
                            }
                        }.labelsHidden()
                    }
                    row("Profile Name") {
                        TextField("Jamf-CLI - Standard", text: $vm.profileName)
                    }
                }

                statusRow(vm: vm, connectingTo: "Jamf Pro")

                Button(vm.isRunningSetup ? "Connecting…" : "Connect") {
                    Task { await vm.runLocalSetup() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!vm.canRunLocalSetup || vm.isRunningSetup)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 36)
        }
    }
}

// MARK: - Pro SSO / OAuth Setup

private struct SSOSetupStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 16)
                    Text("SSO / No Local Accounts")
                        .font(.title2).bold()
                    Text("First, create an API role and client in Jamf Pro, then enter the credentials below.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 400)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Before continuing, in Jamf Pro:")
                        .fontWeight(.medium)
                    Label("Go to **Settings → System → API Roles and Clients**", systemImage: "1.circle.fill")
                    Label("Create an **API Role** with the privileges you need", systemImage: "2.circle.fill")
                    Label("Create an **API Client**, assign your role, and save the **Client ID** and **Client Secret** (shown only once)", systemImage: "3.circle.fill")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.accentColor.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                formRows {
                    row("Server URL") {
                        TextField("https://yourinstance.jamfcloud.com", text: $vm.ssoServerURL)
                    }
                    row("Profile Name") {
                        TextField("Jamf-CLI - SSO", text: $vm.ssoProfileName)
                    }
                    row("Client ID") {
                        TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $vm.ssoClientID)
                            .textContentType(.username)
                    }
                    row("Client Secret") {
                        SecureField("Client Secret", text: $vm.ssoClientSecret)
                            .textContentType(.password)
                    }
                }

                statusRow(vm: vm, connectingTo: "Jamf Pro")

                Button(vm.isRunningSetup ? "Connecting…" : "Connect") {
                    Task { await vm.runSSOSetup() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!vm.canRunSSOSetup || vm.isRunningSetup)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 36)
        }
    }
}

// MARK: - Jamf Protect Setup (OAuth)

private struct ProtectSetupStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 16)
                    Text("Jamf Protect Connection")
                        .font(.title2).bold()
                    Text(JamfProduct.protect.authDescription)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 400)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Before continuing, in Jamf Protect:")
                        .fontWeight(.medium)
                    Label("Go to **Administration → API Clients**", systemImage: "1.circle.fill")
                    Label("Create an API Client and note the **Client ID**", systemImage: "2.circle.fill")
                    Label("Generate a **Client Secret** (shown only once)", systemImage: "3.circle.fill")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.accentColor.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                formRows {
                    row("Server URL") {
                        TextField("https://yourinstance.jamfprotect.com", text: $vm.protectServerURL)
                    }
                    row("Profile Name") {
                        TextField("Jamf Protect", text: $vm.protectProfileName)
                    }
                    row("Client ID") {
                        TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $vm.protectClientID)
                            .textContentType(.username)
                    }
                    row("Client Secret") {
                        SecureField("Client Secret", text: $vm.protectClientSecret)
                            .textContentType(.password)
                    }
                }

                statusRow(vm: vm, connectingTo: "Jamf Protect")

                Button(vm.isRunningSetup ? "Connecting…" : "Connect") {
                    Task { await vm.runProtectSetup() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!vm.canRunProtectSetup || vm.isRunningSetup)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 36)
        }
    }
}

// MARK: - Jamf School Setup (API key)

private struct SchoolSetupStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 16)
                    Text("Jamf School Connection")
                        .font(.title2).bold()
                    Text(JamfProduct.school.authDescription)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 400)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Before continuing, in Jamf School:")
                        .fontWeight(.medium)
                    Label("Go to **Organisation → API**", systemImage: "1.circle.fill")
                    Label("Note your **Network ID** and generate an **API Key**", systemImage: "2.circle.fill")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.accentColor.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                formRows {
                    row("Server URL") {
                        TextField("https://yourschool.jamfcloud.com", text: $vm.schoolServerURL)
                    }
                    row("Profile Name") {
                        TextField("Jamf School", text: $vm.schoolProfileName)
                    }
                    row("Network ID") {
                        TextField("Network ID", text: $vm.schoolNetworkID)
                    }
                    row("API Key") {
                        SecureField("API Key", text: $vm.schoolAPIKey)
                            .textContentType(.password)
                    }
                }

                statusRow(vm: vm, connectingTo: "Jamf School")

                Button(vm.isRunningSetup ? "Connecting…" : "Connect") {
                    Task { await vm.runSchoolSetup() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!vm.canRunSchoolSetup || vm.isRunningSetup)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 36)
        }
    }
}

// MARK: - Shared helpers

@ViewBuilder
private func formRows<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(spacing: 0) {
        content()
    }
    .padding(.vertical, 4)
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
}

@ViewBuilder
private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    HStack {
        Text(label)
            .frame(width: 108, alignment: .trailing)
            .foregroundStyle(.secondary)
        content()
            .textFieldStyle(.roundedBorder)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    Divider().padding(.leading, 120)
}

@MainActor @ViewBuilder
private func statusRow(vm: OnboardingViewModel, connectingTo product: String) -> some View {
    if vm.isRunningSetup {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Connecting to \(product)…").foregroundStyle(.secondary).font(.callout)
        }
    }
    if let error = vm.error {
        Label(error, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red).font(.caption)
            .multilineTextAlignment(.center).frame(maxWidth: 400)
    }
}

// MARK: - Complete

private struct CompleteStep: View {
    let product: JamfProduct
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
                .padding(.top, 24)

            Text("Ready to Go!")
                .font(.title).bold()

            Text("jamf-cli is installed and your **\(product.displayName)** connection is configured.\n\nYou can add more connections or switch profiles anytime from **Settings**.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            Spacer()

            Button("Open Dashboard") { onComplete() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 30)
        }
        .padding(.horizontal, 40)
    }
}
