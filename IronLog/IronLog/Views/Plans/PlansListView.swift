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
                    ContentUnavailableView(
                        "No Plans",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Import a workout plan to get started")
                    )
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
