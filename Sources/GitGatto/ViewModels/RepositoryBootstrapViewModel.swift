import AppKit
import Foundation

@MainActor
final class RepositoryBootstrapViewModel: ObservableObject {
    @Published var folder: URL?
    @Published var accountRefreshID = UUID()
    @Published private(set) var account: GitHubAccount?
    @Published private(set) var accountError: AppErrorReport?
    @Published private(set) var isCheckingAccount = false
    @Published var branch = "main"
    @Published var name = ""
    @Published var owner = ""
    @Published var createRemote = true
    @Published var isPrivate = true
    @Published var connectExisting = false
    @Published var pushInitialCommit = true
    @Published var customIdentity = false
    @Published var authorName = ""
    @Published var authorEmail = ""
    @Published private(set) var inspection: RepositoryBootstrapInspection?
    @Published private(set) var isInspecting = false
    @Published private(set) var isRunning = false
    @Published private(set) var runID: UUID?
    @Published private(set) var steps: [RepositoryBootstrapStep: RepositoryBootstrapEvent.State] = [:]
    @Published private(set) var error: AppErrorReport?
    @Published private(set) var result: RepositoryBootstrapResult?
    @Published var showsConfirmation = false
    @Published var manualOptions = false
    private var pendingRequest: RepositoryBootstrapRequest?
    private var needsAgentDetails = false
    private var preparedAgentRequest: RepositoryBootstrapRequest?
    private var automaticAgent: Bool
    private let agent: any RepositoryConfigurationAgent
    private let service: RepositoryBootstrapService

    init(service: RepositoryBootstrapService = RepositoryBootstrapService(), folder: URL? = nil,
         automaticAgent: Bool = false, manualOptions: Bool = false, agent: any RepositoryConfigurationAgent = CodexService()) {
        self.service = service
        self.agent = agent
        self.folder = folder
        self.automaticAgent = automaticAgent
        self.manualOptions = manualOptions
        self.name = folder?.lastPathComponent ?? ""
    }

    var confirmationText: String {
        guard let request = pendingRequest else { return "" }
        return "\(request.owner)/\(request.name) · \(request.branch)\n" +
            L10n.text(request.isPrivate ? "repository.create.private" : "repository.create.public") + "\n" +
            (request.pushInitialCommit && request.approvedExistingHead != nil
                ? L10n.text("repository.upstream.history_warning") + " (\(request.approvedExistingHead?.prefix(10) ?? ""))\n" : "") +
            (!request.isPrivate ? L10n.text("repository.visibility.public_warning") : "")
    }

    func startAutomaticAgentIfReady() {
        guard automaticAgent, canRunAgent else { return }
        automaticAgent = false
        requestCreate(usingAgent: true)
    }

    var canRunAgent: Bool {
        guard let folder, let inspection else { return false }
        return inspection.folder == folder.standardizedFileURL.resolvingSymlinksInPath()
            && (!createRemote || (account != nil && !isCheckingAccount))
            && !isRunning && !isInspecting && result == nil
    }

    var canCreate: Bool {
        guard let folder, let inspection else { return false }
        return inspection.folder == folder.standardizedFileURL.resolvingSymlinksInPath()
            && (!createRemote || (account != nil && !isCheckingAccount && RepositoryBootstrapService.validName(name)))
            && !isRunning && !isInspecting && result == nil
    }

    func refreshAccount() async {
        guard folder != nil, createRemote, !isRunning else { return }
        let refreshID = accountRefreshID
        account = nil
        accountError = nil
        isCheckingAccount = true
        defer { if accountRefreshID == refreshID { isCheckingAccount = false } }
        do {
            let value = try await service.currentAccount()
            try Task.checkCancellation()
            guard accountRefreshID == refreshID else { return }
            if let origin = inspection?.origin, let remote = try await service.existingRemote(origin) {
                try Task.checkCancellation()
                guard accountRefreshID == refreshID else { return }
                name = remote.name; owner = remote.owner; isPrivate = remote.isPrivate; connectExisting = true
            }
            if owner.isEmpty { owner = value.login }
            account = value
        } catch is CancellationError { }
        catch {
            guard accountRefreshID == refreshID else { return }
            accountError = GlobalErrorHandler.report(for: error, context: .repositoryCreate)
        }
    }

    func chooseFolder() {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.text("repository.create.folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        self.folder = folder
        inspection = nil
        error = nil
        branch = "main"
        name = folder.lastPathComponent
        owner = ""
        result = nil
        steps = [:]
    }

    func inspectFolder() async {
        guard let folder, !isRunning else { return }
        if inspection?.folder == folder.standardizedFileURL.resolvingSymlinksInPath() { return }
        isInspecting = true
        inspection = nil
        error = nil
        defer { if self.folder == folder { isInspecting = false } }
        do {
            let value = try await service.inspect(folder)
            guard !Task.isCancelled, self.folder == folder else { return }
            inspection = value
            if let origin = value.origin, let fullName = GitHubRepositoryVisibilityService.fullName(remote: origin) {
                let parts = fullName.split(separator: "/").map(String.init)
                owner = parts[0]; name = parts[1]; connectExisting = true
            }
            if let branch = value.branch { self.branch = branch }
            pushInitialCommit = value.canPushInitialCommit
            customIdentity = !value.hasHEAD && (value.authorName.isEmpty || value.authorEmail.isEmpty)
            authorName = value.authorName
            authorEmail = value.authorEmail
        } catch is CancellationError { }
        catch {
            guard self.folder == folder else { return }
            self.error = GlobalErrorHandler.report(for: error, context: .repositoryCreate, repositoryURL: folder)
        }
    }

    func requestCreate(usingAgent: Bool = false) {
        guard usingAgent ? canRunAgent : canCreate, let folder else { return }
        self.needsAgentDetails = usingAgent
        pendingRequest = RepositoryBootstrapRequest(folder: folder, branch: branch, createRemote: createRemote,
            name: name, owner: owner.isEmpty ? account?.login ?? "" : owner, isPrivate: isPrivate, connectExisting: connectExisting, pushInitialCommit: pushInitialCommit,
            approvedExistingHead: pushInitialCommit && inspection?.canPushInitialCommit == false ? inspection?.head : nil,
            authorName: customIdentity ? authorName : "", authorEmail: customIdentity ? authorEmail : "")
        if usingAgent, pendingRequest == preparedAgentRequest { needsAgentDetails = false }
        if !needsAgentDetails, createRemote && (!isPrivate || (pushInitialCommit && inspection?.canPushInitialCommit == false)) {
            showsConfirmation = true
        } else { confirmRequest() }
    }

    func confirmRequest() {
        guard pendingRequest != nil, !isRunning else { return }
        showsConfirmation = false
        isRunning = true
        error = nil
        steps = [:]
        runID = UUID()
    }

    func cancelConfirmation() { pendingRequest = nil; showsConfirmation = false }

    func performRequest() async {
        guard let id = runID, isRunning, var request = pendingRequest else { return }
        defer { if runID == id { isRunning = false } }
        do {
            let progress: @Sendable (RepositoryBootstrapEvent) async -> Void = { [weak self] event in
                await self?.record(event, requestID: id)
            }
            if needsAgentDetails {
                request = try await RepositoryUpstreamAgent(agent: agent, service: service).prepare(request, progress: progress)
                try Task.checkCancellation()
                guard runID == id else { return }
                pendingRequest = request; preparedAgentRequest = request; needsAgentDetails = false
                name = request.name; owner = request.owner; branch = request.branch
                isPrivate = request.isPrivate; connectExisting = request.connectExisting
                authorName = request.authorName; authorEmail = request.authorEmail
                customIdentity = !request.authorName.isEmpty
                if request.createRemote && (!request.isPrivate || request.approvedExistingHead != nil) {
                    showsConfirmation = true
                    return
                }
            }
            let value = try await service.create(request, progress: progress)
            guard runID == id else { return }
            result = value
        } catch {
            guard runID == id else { return }
            self.error = GlobalErrorHandler.report(for: error, context: .repositoryCreate, repositoryURL: request.folder)
        }
    }

    private func record(_ event: RepositoryBootstrapEvent, requestID: UUID) {
        guard runID == requestID else { return }
        steps[event.step] = event.state
    }
}
