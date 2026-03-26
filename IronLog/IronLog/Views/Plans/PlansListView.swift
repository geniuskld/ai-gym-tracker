import SwiftUI
import SwiftData

struct PlansListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SDPlan.importedAt, order: .reverse) private var plans: [SDPlan]
    @State private var vm = PlansViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if plans.isEmpty {
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
                } else {
                    List {
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
        }
    }

    private func deletePlans(at offsets: IndexSet) {
        for index in offsets {
            vm.deletePlan(plans[index], context: context)
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

// MARK: - Plan Row

private struct PlanRow: View {
    let plan: SDPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.planName)
                .font(.headline)

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
