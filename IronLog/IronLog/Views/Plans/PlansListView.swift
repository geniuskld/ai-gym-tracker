import SwiftUI
import SwiftData

struct PlansListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SDPlan.importedAt, order: .reverse) private var strengthPlans: [SDPlan]
    @Query(sort: \SDCyclingPlan.importedAt, order: .reverse) private var cyclingPlans: [SDCyclingPlan]
    @State private var vm = PlansViewModel()
    @State private var syncErrorMessage: String?
    @AppStorage(PlanSelectionKey.storageKey) private var selectedPlanKey: String = ""
    @AppStorage(PlanSelectionKey.legacyStorageKey) private var legacySelectedPlanId: String = ""

    private var hasAnyPlans: Bool {
        !strengthPlans.isEmpty || !cyclingPlans.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasAnyPlans {
                    emptyState
                } else {
                    List {
                        if !strengthPlans.isEmpty {
                            Section("Strength") {
                                ForEach(strengthPlans) { plan in
                                    PlanRow(
                                        plan: plan,
                                        isSelected: PlanSelectionKey.matches(
                                            selection: selectedPlanKey,
                                            legacyPlanId: legacySelectedPlanId,
                                            type: .strength,
                                            planId: plan.planId
                                        )
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedPlanKey = PlanSelectionKey.make(
                                            type: .strength,
                                            planId: plan.planId
                                        )
                                    }
                                }
                                .onDelete(perform: deleteStrength)
                            }
                        }
                        if !cyclingPlans.isEmpty {
                            Section("Cycling") {
                                ForEach(cyclingPlans) { plan in
                                    CyclingPlanRow(
                                        plan: plan,
                                        isSelected: PlanSelectionKey.matches(
                                            selection: selectedPlanKey,
                                            legacyPlanId: legacySelectedPlanId,
                                            type: .cycling,
                                            planId: plan.planId
                                        )
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedPlanKey = PlanSelectionKey.make(
                                            type: .cycling,
                                            planId: plan.planId
                                        )
                                    }
                                }
                                .onDelete(perform: deleteCycling)
                            }
                        }
                    }
                    .refreshable {
                        let error = await PlanSyncHelper.syncIfNeeded(
                            context: context,
                            force: true
                        )
                        syncErrorMessage = error?.localizedDescription
                    }
                }
            }
            .navigationTitle("Plans")
            .onAppear(perform: migrateLegacySelectionIfNeeded)
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
                    PlanPreviewView(vm: vm, parsed: plan)
                }
            }
            .alert(
                "Sync Failed",
                isPresented: Binding(
                    get: { syncErrorMessage != nil },
                    set: { if !$0 { syncErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    syncErrorMessage = nil
                }
            } message: {
                Text(syncErrorMessage ?? "")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

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
    }

    private func deleteStrength(at offsets: IndexSet) {
        for index in offsets {
            vm.deletePlan(strengthPlans[index], context: context)
        }
    }

    private func deleteCycling(at offsets: IndexSet) {
        for index in offsets {
            vm.deleteCyclingPlan(cyclingPlans[index], context: context)
        }
    }

    private func migrateLegacySelectionIfNeeded() {
        guard selectedPlanKey.isEmpty, !legacySelectedPlanId.isEmpty else {
            return
        }
        if strengthPlans.contains(where: { $0.planId == legacySelectedPlanId }) {
            selectedPlanKey = PlanSelectionKey.make(
                type: .strength,
                planId: legacySelectedPlanId
            )
        } else if cyclingPlans.contains(where: { $0.planId == legacySelectedPlanId }) {
            selectedPlanKey = PlanSelectionKey.make(
                type: .cycling,
                planId: legacySelectedPlanId
            )
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

// MARK: - Strength Plan Row

private struct PlanRow: View {
    let plan: SDPlan
    let isSelected: Bool

    var body: some View {
        HStack {
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

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Cycling Plan Row

private struct CyclingPlanRow: View {
    let plan: SDCyclingPlan
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "bicycle")
                        .foregroundStyle(.secondary)
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
                        "\(plan.templates.count) workouts",
                        systemImage: "calendar"
                    )
                    if let mhr = plan.maxHrBpm {
                        Label("max \(mhr)", systemImage: "heart")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(plan.importedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }
}
