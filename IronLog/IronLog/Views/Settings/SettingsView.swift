import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("syncServerURL") private var serverURL = SyncService.defaultServerURL
    @State private var editingURL = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isAuthLoading = false
    @State private var isAuthenticated = SyncService.isAuthenticated
    @State private var authMessage: AuthMessage?
    @State private var testResult: TestResult?
    @State private var isTesting = false

    enum TestResult {
        case success(String)
        case failure(String)
    }

    struct AuthMessage: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                serverSection
                connectionActionsSection

                if let result = testResult {
                    testStatusSection(result)
                }

                accountSection

                if let msg = authMessage {
                    SettingsStatusCard(
                        text: msg.text,
                        systemImage: msg.isError
                            ? "xmark.circle.fill"
                            : "checkmark.circle.fill",
                        tint: msg.isError
                            ? CockpitPalette.red
                            : CockpitPalette.green
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CockpitPalette.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CockpitPalette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            editingURL = serverURL
            isAuthenticated = SyncService.isAuthenticated
        }
    }

    private var serverSection: some View {
        CockpitPanel(spacing: 10, padding: 16) {
            Text("Sync Server URL")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            TextField("https://example.com/api", text: $editingURL)
                .keyboardType(.URL)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .settingsInputShell()

            Text("Base URL for plan sync and log upload")
                .font(.caption)
                .foregroundStyle(CockpitPalette.muted)
        }
    }

    private var connectionActionsSection: some View {
        CockpitPanel(spacing: 12, padding: 16) {
            HStack(spacing: 12) {
                Button {
                    saveURL()
                } label: {
                    Label("Save", systemImage: "checkmark")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(CockpitPrimaryButtonStyle(tint: CockpitPalette.blue))
                .disabled(editingURL == serverURL)
                .opacity(editingURL == serverURL ? 0.45 : 1)

                Button {
                    testConnection()
                } label: {
                    HStack(spacing: 8) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(CockpitPalette.blue)
                            Text("Testing...")
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Test")
                        }
                    }
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(CockpitPalette.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        CockpitPalette.panelElevated,
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(CockpitPalette.border)
                    }
                }
                .buttonStyle(.plain)
                .disabled(editingURL.isEmpty || isTesting)
                .opacity(editingURL.isEmpty || isTesting ? 0.45 : 1)
            }
        }
    }

    @ViewBuilder
    private func testStatusSection(_ result: TestResult) -> some View {
        switch result {
        case .success(let msg):
            SettingsStatusCard(
                text: msg,
                systemImage: "checkmark.circle.fill",
                tint: CockpitPalette.green
            )
        case .failure(let msg):
            SettingsStatusCard(
                text: msg,
                systemImage: "xmark.circle.fill",
                tint: CockpitPalette.red
            )
        }
    }

    private var accountSection: some View {
        CockpitPanel(spacing: 14, padding: 16) {
            Text("Account")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            if isAuthenticated {
                signedInAccountRow
            } else {
                authForm
            }
        }
    }

    private var signedInAccountRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(CockpitPalette.green)

            Text(SyncService.savedEmail ?? "Signed in")
                .font(.headline.weight(.semibold))
                .foregroundStyle(CockpitPalette.green)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            Button("Sign Out") {
                SyncService.logout()
                isAuthenticated = false
                authMessage = AuthMessage(
                    text: "Signed out",
                    isError: false
                )
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(CockpitPalette.red)
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(CockpitPalette.panelElevated, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(CockpitPalette.border)
        }
    }

    private var authForm: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .settingsInputShell()

            SecureField("Password", text: $password)
                .textContentType(.password)
                .settingsInputShell()

            HStack(spacing: 12) {
                Button {
                    authenticate(isRegister: false)
                } label: {
                    HStack(spacing: 8) {
                        if isAuthLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "person.fill.checkmark")
                        }
                        Text("Sign In")
                    }
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(CockpitPrimaryButtonStyle(tint: CockpitPalette.blue))
                .disabled(authButtonsDisabled)
                .opacity(authButtonsDisabled ? 0.45 : 1)

                Button {
                    authenticate(isRegister: true)
                } label: {
                    Text("Create")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(CockpitPalette.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            CockpitPalette.panelElevated,
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(CockpitPalette.border)
                        }
                }
                .buttonStyle(.plain)
                .disabled(authButtonsDisabled)
                .opacity(authButtonsDisabled ? 0.45 : 1)
            }
        }
    }

    private var authButtonsDisabled: Bool {
        email.isEmpty || password.isEmpty || isAuthLoading
    }

    // MARK: - Actions

    private func saveURL() {
        let trimmed = editingURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        serverURL = trimmed.hasSuffix("/")
            ? String(trimmed.dropLast())
            : trimmed
        editingURL = serverURL
        SyncService.serverURL = serverURL
    }

    private func testConnection() {
        saveURL()
        testResult = nil
        isTesting = true

        Task {
            do {
                let plans = try await SyncService.fetchPlans()
                if plans.isEmpty {
                    testResult = .success("Connected (no plans)")
                } else {
                    let preview = plans
                        .prefix(3)
                        .map { "\($0.planName) v\($0.planVersion) [\($0.planType)]" }
                        .joined(separator: ", ")
                    let suffix = plans.count > 3 ? " +\(plans.count - 3)" : ""
                    testResult = .success("\(plans.count) plans: \(preview)\(suffix)")
                }
            } catch {
                testResult = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }

    private func authenticate(isRegister: Bool) {
        saveURL()
        authMessage = nil
        isAuthLoading = true

        Task {
            do {
                let result: AuthResponse
                if isRegister {
                    result = try await SyncService.register(
                        email: email,
                        password: password
                    )
                } else {
                    result = try await SyncService.login(
                        email: email,
                        password: password
                    )
                }
                authMessage = AuthMessage(
                    text: "Signed in as \(result.email)",
                    isError: false
                )
                isAuthenticated = true
                password = ""
                await WorkoutSyncService.retryPending(
                    context: modelContext,
                    force: true
                )
            } catch {
                authMessage = AuthMessage(
                    text: error.localizedDescription,
                    isError: true
                )
            }
            isAuthLoading = false
        }
    }
}

private struct SettingsInputShell: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
            .tint(CockpitPalette.blue)
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(
                CockpitPalette.panelElevated,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(CockpitPalette.border)
            }
    }
}

private extension View {
    func settingsInputShell() -> some View {
        modifier(SettingsInputShell())
    }
}

private struct SettingsStatusCard: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)

            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(tint.opacity(0.28))
        }
    }
}
