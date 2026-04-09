import SwiftUI

struct SettingsView: View {
    @AppStorage("syncServerURL") private var serverURL = ""
    @State private var editingURL = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isAuthLoading = false
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
        Form {
            // Server URL
            Section {
                TextField("https://example.com/api", text: $editingURL)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Sync Server URL")
            } footer: {
                Text("Base URL for plan sync and log upload")
            }

            Section {
                Button {
                    saveURL()
                } label: {
                    Text("Save")
                        .fontWeight(.semibold)
                }
                .disabled(editingURL == serverURL)

                Button {
                    testConnection()
                } label: {
                    if isTesting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Testing...")
                        }
                    } else {
                        Label(
                            "Test Connection",
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                    }
                }
                .disabled(editingURL.isEmpty || isTesting)
            }

            if let result = testResult {
                Section {
                    switch result {
                    case .success(let msg):
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let msg):
                        Label(msg, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }

            // Account
            Section {
                if SyncService.isAuthenticated {
                    HStack {
                        Label(
                            SyncService.savedEmail ?? "Signed in",
                            systemImage: "person.circle.fill"
                        )
                        .foregroundStyle(.green)
                        Spacer()
                        Button("Sign Out") {
                            SyncService.logout()
                            authMessage = AuthMessage(
                                text: "Signed out",
                                isError: false
                            )
                        }
                        .foregroundStyle(.red)
                    }
                } else {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("Password", text: $password)
                        .textContentType(.password)

                    HStack {
                        Button {
                            authenticate(isRegister: false)
                        } label: {
                            if isAuthLoading {
                                ProgressView()
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(
                            email.isEmpty
                            || password.isEmpty
                            || isAuthLoading
                        )

                        Spacer()

                        Button("Create Account") {
                            authenticate(isRegister: true)
                        }
                        .disabled(
                            email.isEmpty
                            || password.isEmpty
                            || isAuthLoading
                        )
                    }
                }
            } header: {
                Text("Account")
            }

            if let msg = authMessage {
                Section {
                    Label(
                        msg.text,
                        systemImage: msg.isError
                            ? "xmark.circle.fill"
                            : "checkmark.circle.fill"
                    )
                    .foregroundStyle(msg.isError ? .red : .green)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            editingURL = serverURL
        }
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
                let plan = try await SyncService.fetchPlan()
                testResult = .success(
                    "\(plan.planName) v\(plan.planVersion)"
                )
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
                password = ""
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
