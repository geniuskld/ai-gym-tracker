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
                            Section {
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
                                    .listRowInsets(
                                        EdgeInsets(
                                            top: 6,
                                            leading: 16,
                                            bottom: 6,
                                            trailing: 16
                                        )
                                    )
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedPlanKey = PlanSelectionKey.make(
                                            type: .strength,
                                            planId: plan.planId
                                        )
                                    }
                                }
                                .onDelete(perform: deleteStrength)
                            } header: {
                                Text("Strength")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(CockpitPalette.muted)
                            }
                        }
                        if !cyclingPlans.isEmpty {
                            Section {
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
                                    .listRowInsets(
                                        EdgeInsets(
                                            top: 6,
                                            leading: 16,
                                            bottom: 6,
                                            trailing: 16
                                        )
                                    )
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedPlanKey = PlanSelectionKey.make(
                                            type: .cycling,
                                            planId: plan.planId
                                        )
                                    }
                                }
                                .onDelete(perform: deleteCycling)
                            } header: {
                                Text("Cycling")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(CockpitPalette.muted)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(CockpitPalette.background)
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
            .toolbarBackground(CockpitPalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
                        .foregroundStyle(CockpitPalette.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(CockpitPalette.panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(CockpitPalette.border)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            #if DEBUG
            Button {
                loadSamplePlan()
            } label: {
                Label("Load Sample Plan", systemImage: "doc.text")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        CockpitPalette.amber.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(CockpitPalette.amber.opacity(0.28))
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(CockpitPalette.amber)
            #endif

            Spacer()
        }
        .padding()
        .background(CockpitPalette.background.ignoresSafeArea())
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
        HStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(CockpitPalette.blue)
                .frame(width: 38, height: 38)
                .background(
                    CockpitPalette.blue.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plan.planName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text("v\(plan.planVersion)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CockpitPalette.muted)
                }

                HStack(spacing: 8) {
                    if let author = plan.author {
                        CockpitChip(
                            text: author,
                            color: CockpitPalette.muted,
                            systemImage: "person"
                        )
                    }
                    CockpitChip(
                        text: "\(plan.templates.count) templates",
                        color: CockpitPalette.blue,
                        systemImage: "calendar"
                    )
                }

                Text(plan.importedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(CockpitPalette.faint)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(CockpitPalette.green)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CockpitPalette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isSelected
                        ? CockpitPalette.green.opacity(0.45)
                        : CockpitPalette.border
                )
        }
    }
}

// MARK: - Cycling Plan Row

private struct CyclingPlanRow: View {
    let plan: SDCyclingPlan
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bicycle")
                .font(.headline.weight(.semibold))
                .foregroundStyle(CockpitPalette.cyan)
                .frame(width: 38, height: 38)
                .background(
                    CockpitPalette.cyan.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plan.planName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text("v\(plan.planVersion)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CockpitPalette.muted)
                }

                HStack(spacing: 8) {
                    if let author = plan.author {
                        CockpitChip(
                            text: author,
                            color: CockpitPalette.muted,
                            systemImage: "person"
                        )
                    }
                    CockpitChip(
                        text: "\(plan.templates.count) workouts",
                        color: CockpitPalette.cyan,
                        systemImage: "calendar"
                    )
                    if let mhr = plan.maxHrBpm {
                        CockpitChip(
                            text: "max \(mhr)",
                            color: CockpitPalette.red,
                            systemImage: "heart"
                        )
                    }
                }

                Text(plan.importedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(CockpitPalette.faint)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(CockpitPalette.green)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CockpitPalette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isSelected
                        ? CockpitPalette.green.opacity(0.45)
                        : CockpitPalette.border
                )
        }
    }
}
