import SwiftUI
import SwiftData

struct PlansListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SDPlan.importedAt, order: .reverse) private var plans: [SDPlan]
    @State private var vm = PlansViewModel()
    @State private var isSyncing = false
    @State private var syncAlert: SyncAlertItem?

    var body: some View {
        NavigationStack {
            Group {
                if plans.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()

                        if SyncService.isConfigured {
                            Button {
                                syncPlan()
                            } label: {
                                VStack(spacing: 12) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 48))
                                    Text("Sync Plan from Server")
                                        .font(.title3.weight(.semibold))
                                    Text("Pull the latest version")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 32)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                        }

                        Button {
                            vm.showImportSheet = true
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: "dumbbell.fill")
                                    .font(.system(size: 48))
                                Text("Import Your Program")
                                    .font(.title3.weight(.semibold))
                                Text("Paste or pick a JSON training plan")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)

                        #if DEBUG
                        Button {
                            loadSamplePlan()
                        } label: {
                            Label("Load Sample Plan", systemImage: "doc.text")
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        #endif

                        Spacer()
                    }
                    .padding()
                } else {
                    List {
                        // Sync banner
                        if SyncService.isConfigured {
                            Section {
                                Button {
                                    syncPlan()
                                } label: {
                                    HStack {
                                        Label(
                                            "Sync Plan",
                                            systemImage: "arrow.triangle.2.circlepath"
                                        )
                                        .foregroundStyle(.blue)
                                        Spacer()
                                        if isSyncing {
                                            ProgressView()
                                        }
                                    }
                                }
                                .disabled(isSyncing)
                            }
                        }

                        ForEach(plans) { plan in
                            PlanRow(plan: plan)
                        }
                        .onDelete(perform: deletePlans)
                    }
                }
            }
            .navigationTitle("Plans")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        vm.showImportSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $vm.showImportSheet) {
                ImportView(vm: vm)
            }
            .navigationDestination(isPresented: $vm.showPreview) {
                if let plan = vm.parsedPlan {
                    PlanPreviewView(vm: vm, plan: plan)
                }
            }
            .alert(
                item: $syncAlert
            ) { item in
                Alert(
                    title: Text(item.title),
                    message: Text(item.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func deletePlans(at offsets: IndexSet) {
        for index in offsets {
            vm.deletePlan(plans[index], context: context)
        }
    }

    private func syncPlan() {
        isSyncing = true
        Task {
            do {
                let json = try await SyncService.fetchPlan()
                // Check if we already have this version
                let existing = plans.first {
                    $0.planId == json.planId && $0.planType == json.planType
                }
                if let existing, existing.planVersion >= json.planVersion {
                    syncAlert = SyncAlertItem(
                        title: "Up to date",
                        message: "\(json.planName) v\(json.planVersion) -- already imported"
                    )
                } else {
                    _ = try PlanImportService.importPlan(
                        json,
                        into: context,
                        replaceExisting: true
                    )
                    syncAlert = SyncAlertItem(
                        title: "Updated",
                        message: "\(json.planName) v\(json.planVersion)"
                    )
                }
            } catch {
                syncAlert = SyncAlertItem(
                    title: "Sync failed",
                    message: error.localizedDescription
                )
            }
            isSyncing = false
        }
    }

    #if DEBUG
    private func loadSamplePlan() {
        guard let url = Bundle.main.url(
            forResource: "sample-plan",
            withExtension: "json"
        ) else { return }
        vm.parseFromFile(url)
    }
    #endif
}

private struct SyncAlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Plan Row

private struct PlanRow: View {
    let plan: SDPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.planName)
                    .font(.headline)
                Text("v\(plan.planVersion)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack {
                if let author = plan.author {
                    Label(author, systemImage: "person")
                }
                Label(
                    "\(plan.templates.count) templates",
                    systemImage: "calendar"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(plan.importedAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
