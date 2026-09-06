import AppKit
import Foundation
import SwiftUI
import Testing
@testable import GitGatto

@Suite("GitHub workflow authorization", .serialized)
struct GitHubAuthorizationTests {
    @Test("Sign-in requests workflow access and refresh preserves the existing Git protocol")
    func requestsOnlyRequiredAdditionalScope() {
        #expect(GitHubAuthorizationRequest.signIn.arguments == [
            "auth", "login", "--hostname", "github.com", "--web", "--clipboard",
            "--git-protocol", "ssh", "--skip-ssh-key", "--scopes", "workflow"
        ])
        #expect(GitHubAuthorizationRequest.workflowPermission.arguments == [
            "auth", "refresh", "--hostname", "github.com", "--scopes", "workflow", "--clipboard"
        ])
    }

    @Test("The Terminal command preserves argv when the CLI path contains quotes and spaces")
    func quotesCommandArguments() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGatto-Auth-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("developer's gh fixture")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\"\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        for request in [GitHubAuthorizationRequest.signIn, .workflowPermission] {
            let result = try await ExternalProcessRunner().run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", request.shellCommand(executableURL: executable)],
                timeout: .seconds(5)
            )
            #expect(result.outputText.split(whereSeparator: \.isNewline).map(String.init) == request.arguments)
        }
    }

    @Test("Explicit rejection evidence distinguishes scopes, divergence and unknown rejection", arguments: [
        ("refusing to allow a Personal Access Token to create or update workflow 'ci.yml' without 'workflow' scope", GitPushRejection.workflowScope),
        ("! [rejected] main -> main (fetch first)", GitPushRejection.nonFastForward),
        ("! [rejected] main -> main (non-fast-forward)", GitPushRejection.nonFastForward),
        ("hint: the tip of your current branch is behind its remote counterpart", GitPushRejection.nonFastForward)
    ])
    func classifiesExplicitEvidence(message: String, expected: GitPushRejection) {
        #expect(GitPushRejection(message: message) == expected)
    }

    @MainActor
    @Test("The authorization action launches once and reports only that the flow opened")
    func launchesAuthorizationOnce() async throws {
        let service = try GitHubAgentReplyGitHubFixture()
        let model = WorkspaceViewModel(githubService: service)
        model.beginGitHubLogin(.workflowPermission)
        model.beginGitHubLogin(.workflowPermission)
        #expect(model.isLaunchingGitHubLogin)
        try await waitUntil { !model.isLaunchingGitHubLogin }
        #expect(await service.authorizationRequests == [.workflowPermission])
        #expect(model.githubActivity == L10n.text("github.status.workflow_opened"))
        #expect(model.githubError == nil)
        #expect(model.githubAccount == nil)

        let failedService = try GitHubAgentReplyGitHubFixture(failsAuthorization: true)
        let failed = WorkspaceViewModel(githubService: failedService)
        failed.beginGitHubLogin(.workflowPermission)
        try await waitUntil { !failed.isLaunchingGitHubLogin }
        #expect(failed.githubActivity == nil)
        #expect(failed.githubError != nil)
    }

    @MainActor
    @Test("Renders account authorization states at narrow and wide widths")
    func rendersAuthorizationStates() async throws {
        let environment = ProcessInfo.processInfo.environment
        let originalLanguage = AppPreferencesStore.load().language
        let language = environment["GITGATTO_AUTH_UI_LANGUAGE"].flatMap(AppLanguage.init(rawValue:))
        if let language { L10n.activate(language) }
        defer { if language != nil { L10n.activate(originalLanguage) } }
        let isRTL = language?.usesRightToLeftLayout ?? false
        for state in ["signed-out", "signed-in", "launching", "checking", "error", "opened"] {
            let service = try GitHubAgentReplyGitHubFixture(
                authorized: state != "signed-out", failsAuthorization: state == "error"
            )
            let model = WorkspaceViewModel(githubService: service)
            model.retryGitHubProbe()
            try await waitUntil {
                model.githubAvailability.state != .checking && (state == "signed-out" || model.githubAccount != nil)
            }
            if ["error", "opened"].contains(state) {
                model.beginGitHubLogin(.workflowPermission)
                try await waitUntil { !model.isLaunchingGitHubLogin }
            } else if state == "launching" {
                model.beginGitHubLogin(.workflowPermission)
            } else if state == "checking" {
                model.retryGitHubProbe()
            }
            for width in [CGFloat(360), 680] {
                for scheme in [ColorScheme.light, .dark] {
                    let view = VStack(alignment: .leading, spacing: 12) {
                        GitHubAccountSettings(model: model)
                        Spacer(minLength: 0)
                    }
                    .padding(20)
                    .frame(width: width, height: 260, alignment: .topLeading)
                    .background(AppPalette(scheme).background)
                    .environment(\.colorScheme, scheme)
                    .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 260),
                                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                    let host = NSHostingView(rootView: view)
                    window.contentView = host
                    window.orderFront(nil)
                    defer { window.orderOut(nil); window.contentView = nil }
                    host.layoutSubtreeIfNeeded()
                    host.displayIfNeeded()
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let data = try #require(bitmap.representation(using: .png, properties: [:]))
                    #expect(data.count > 1_000)
                    if let directory = environment["GITGATTO_AUTH_UI_OUTPUT"] {
                        let output = URL(fileURLWithPath: directory)
                        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                        try data.write(to: output.appendingPathComponent("\(state)-\(Int(width))-\(scheme).png"))
                    }

                }
            }
            try await waitUntil { !model.isLaunchingGitHubLogin && model.githubAvailability.state != .checking }
        }
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            if ContinuousClock.now >= deadline { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
