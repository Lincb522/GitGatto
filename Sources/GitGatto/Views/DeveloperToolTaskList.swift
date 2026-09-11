import SwiftUI

struct DeveloperToolTaskList: View {
    @ObservedObject var model: DeveloperToolsViewModel
    @State private var pendingResume: DevelopmentToolTaskRecord?
    @State private var historyLimit = 20

    private var visibleRecords: [DevelopmentToolTaskRecord] {
        Array(model.taskRecords.filter(\.needsReview).reversed()) + Array(model.taskRecords.filter { !$0.needsReview }.reversed().prefix(historyLimit))
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("developer_tools.tasks.title")).font(.headline)
            if let error = model.taskPersistenceError {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if model.taskRecords.isEmpty {
                Text(L10n.text("developer_tools.tasks.empty")).foregroundStyle(.secondary)
            }
            ForEach(visibleRecords) { record in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(DevelopmentTool.catalog.first { $0.id == record.toolID }?.name ?? record.toolID)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(L10n.text("developer_tools.tasks." + record.state.rawValue)).font(.caption)
                    }
                    Text(record.updatedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                    if let path = record.executablePath {
                        Text(path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let version = record.version { Text(version).font(.caption).textSelection(.enabled) }
                    if let receipt = record.receipt { DevelopmentToolReceiptView(receipt: receipt) }
                    if record.state == .interrupted {
                        Text(L10n.text("developer_tools.tasks.interruptedHelp"))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(L10n.text("developer_tools.tasks.resume")) { pendingResume = record }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(DevelopmentTool.catalog.first { $0.id == record.toolID }.map(model.isQueuedOrRunning) ?? true)
                            Button(L10n.text("action.cancel")) { model.dismissInterruptedTask(record) }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    } else if record.state == .queued || record.state == .running,
                              let tool = DevelopmentTool.catalog.first(where: { $0.id == record.toolID }) {
                        Button(L10n.text("action.cancel")) { model.cancel(tool) }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(.vertical, 10)
                Divider()
            }
            if model.taskRecords.filter({ !$0.needsReview }).count > historyLimit {
                Button(L10n.text("action.load_more")) { historyLimit += 20 }.buttonStyle(SecondaryButtonStyle())
            }
        }
        .confirmationDialog(L10n.text("developer_tools.tasks.resume"), isPresented: Binding(
            get: { pendingResume != nil }, set: { if !$0 { pendingResume = nil } }
        ), titleVisibility: .visible) {
            Button(L10n.text("developer_tools.tasks.resume")) {
                if let record = pendingResume { model.resumeTask(record) }
                pendingResume = nil
            }
            Button(L10n.text("action.cancel"), role: .cancel) { pendingResume = nil }
        } message: { Text(L10n.text("developer_tools.tasks.interruptedHelp")) }
    }
}
