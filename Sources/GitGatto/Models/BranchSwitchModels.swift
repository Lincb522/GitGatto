import Foundation

struct BranchSwitchRequest: Identifiable {
    let id = UUID()
    let repository: URL
    let targetBranch: String
}

struct WorkSceneSwitchPreview: Sendable {
    let repository: URL
    let branch: String
    let targetBranch: String
    let targetHead: String
    let fingerprint: String
    let changes: [WorkingTreeChange]
}

struct BranchWorkspaceDraft: Sendable {
    var commitMessage = ""
    var agentPrompt = ""
    var selectedPath: String?
    var selectedCommitID: String?
    var goalID: UUID?
    var section = WorkspaceSection.changes
    var updatedAt = Date()
}

struct WorkSceneSwitchFailure: LocalizedError, Sendable {
    let scene: WorkScene
    let reason: String
    var errorDescription: String? {
        L10n.text("branches.scene.switchFailed") + "\n" + reason
    }
}
