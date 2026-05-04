import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Bindable var vm: PlansViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var jsonText = ""
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextEditor(text: $jsonText)
                    .font(.system(.caption, design: .monospaced))
                    .border(Color.secondary.opacity(0.3))
                    .frame(minHeight: 200)

                HStack(spacing: 12) {
                    Button {
                        vm.parseFromClipboard()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("File", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                #if DEBUG
                if let sampleURL = Bundle.main.url(
                    forResource: "sample-plan",
                    withExtension: "json"
                ) {
                    Button {
                        vm.parseFromFile(sampleURL)
                    } label: {
                        Label("Load Sample", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
                #endif

                if !jsonText.isEmpty {
                    Button {
                        vm.parseJSON(jsonText)
                    } label: {
                        Text("Parse JSON")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Import Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.json],
                onCompletion: { result in
                    switch result {
                    case .success(let url):
                        let didAccess = url.startAccessingSecurityScopedResource()
                        defer {
                            if didAccess {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }
                        vm.parseFromFile(url)
                    case .failure(let error):
                        vm.state = .error(error.localizedDescription)
                    }
                }
            )
            .alert(
                "Import Error",
                isPresented: .init(
                    get: { vm.errorMessage != nil },
                    set: { if !$0 { vm.state = .idle } }
                )
            ) {
                Button("OK") { vm.state = .idle }
            } message: {
                if let msg = vm.errorMessage {
                    Text(msg)
                }
            }
        }
    }
}
