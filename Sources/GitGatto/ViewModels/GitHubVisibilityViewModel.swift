import Foundation

@MainActor
final class GitHubVisibilityViewModel: ObservableObject {
    @Published private(set) var state: GitHubVisibilityState?
    @Published private(set) var isBusy = false
    @Published private(set) var error: AppErrorReport?
    @Published var showsConfirmation = false
    @Published private(set) var actionID: UUID?
    private var pending: GitHubVisibilityState?
    private var repository = ""
    private let service: GitHubRepositoryVisibilityService

    init(service: GitHubRepositoryVisibilityService = GitHubRepositoryVisibilityService()) { self.service = service }

    func load(_ fullName: String, force: Bool = false) async {
        guard !isBusy else { return }
        if !force, repository == fullName, state != nil { return }
        repository = fullName
        state = nil; error = nil; isBusy = true
        defer { isBusy = false }
        do {
            let value = try await service.load(fullName)
            try Task.checkCancellation()
            state = value
        } catch is CancellationError { }
        catch { self.error = GlobalErrorHandler.report(for: error, context: .github) }
    }

    func requestChange() {
        guard let state, state.canChange, !isBusy else { return }
        pending = state
        showsConfirmation = true
    }

    var confirmationText: String {
        guard let pending else { return "" }
        return pending.fullName + "\n" + L10n.text(pending.isPrivate
            ? "repository.visibility.public_warning" : "repository.visibility.private_warning")
    }

    func confirmChange() {
        guard pending != nil, !isBusy else { return }
        showsConfirmation = false
        isBusy = true; error = nil; actionID = UUID()
    }

    func performChange() async -> GitHubVisibilityState? {
        guard let pending, isBusy else { return nil }
        defer { isBusy = false; self.pending = nil }
        do {
            let value = try await service.change(pending, toPrivate: !pending.isPrivate)
            guard repository.caseInsensitiveCompare(value.fullName) == .orderedSame else { return nil }
            state = value
            return value
        } catch {
            self.error = GlobalErrorHandler.report(for: error, context: .github)
            return nil
        }
    }
}
