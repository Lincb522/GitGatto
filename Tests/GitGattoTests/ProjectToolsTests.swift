import AppKit
import Foundation
import Combine
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Project tools", .serialized)
struct ProjectToolsTests {
    @Test("Searches multiple repositories, literal text, revisions, history and unusual filenames")
    func search() async throws {
        let a = try await fixture(), b = try await fixture()
        defer { remove(a); remove(b) }
        try write("needle one\nneedle two\n", "odd\nname.swift", a)
        _ = try await git(a, ["add", "."]); _ = try await git(a, ["commit", "-m", "needle addition"])
        try write("needle secret", ".env", a)
        try write("needle", "other.swift", b)
        var query = ProjectCodeQuery(); query.text = "needle"
        let service = ProjectCodeSearchService()
        let results = try await service.search(query, repositories: [a, b])
        #expect(results.matches.count == 3)
        #expect(!results.matches.contains { $0.path == ".env" })
        #expect(results.matches.contains { $0.path == "odd\nname.swift" && $0.line == 2 })
        query.scope = .revision
        let revision = try await service.search(query, repositories: [a])
        #expect(revision.matches.count == 2)
        #expect(try await service.preview(#require(revision.matches.first)).contains("needle"))
        query.scope = .history
        #expect(try await service.search(query, repositories: [a]).matches.count == 1)
        query.scope = .working; query.filenamesOnly = true; query.text = "other"
        #expect(try await service.search(query, repositories: [b]).matches.first?.path == "other.swift")
    }

    @Test("Search reports partial failures, honors limits and rejects traversal")
    func searchBoundaries() async throws {
        let root = try await fixture(); defer { remove(root) }
        try write("needle\nneedle\n", "match.txt", root)
        var query = ProjectCodeQuery(); query.text = "needle"
        let service = ProjectCodeSearchService()
        let results = try await service.search(query, repositories: [root.appendingPathComponent("missing"), root], limit: 1)
        #expect(results.matches.count == 1 && results.limited && results.failures.count == 1)
        await #expect(throws: (any Error).self) { try await service.preview(ProjectCodeMatch(repository: root, path: "../outside", line: 1, text: "", revision: nil)) }
        try write("needle", "component.tsx", root)
        query.language = "TypeScript"
        #expect(try await service.search(query, repositories: [root]).matches.map(\.path) == ["component.tsx"])
        query.language = ""
        try write(String(repeating: "x", count: 100_000), "minified.js", root)
        let preview = try await service.preview(ProjectCodeMatch(repository: root, path: "minified.js", line: 1, text: "", revision: nil))
        #expect(preview.count < 3000)
        query.scope = .revision; query.revision = "--all"
        #expect(try await service.search(query, repositories: [root]).failures.count == 1)
    }

    @Test("Scene preserves staged, unstaged and untracked changes and restores the exact branch")
    func sceneRoundTrip() async throws {
        let root = try await fixture(); defer { remove(root) }
        let store = ProjectToolsStore(root: root.appendingPathComponent(".git/tools")); let service = WorkSceneService(store: store)
        try write("staged\n", "base.txt", root); _ = try await git(root, ["add", "base.txt"])
        try write("staged\nunstaged\n", "base.txt", root); try write("untracked", "new file.txt", root)
        let index = try await git(root, ["diff", "--cached"]), work = try await git(root, ["diff"])
        let scene = try await service.save(name: "feature", repository: root, draft: "draft", agentDraft: "agent", selectedPath: "base.txt", goalID: nil, relatedURL: "", section: "changes")
        #expect(try await git(root, ["status", "--porcelain"]).isEmpty)
        #expect(scene.stash != nil && scene.phase == .saved)
        _ = try await git(root, ["switch", "-c", "other"])
        try await service.restore(scene)
        #expect(try await git(root, ["branch", "--show-current"]) == scene.branch)
        #expect(try await git(root, ["diff", "--cached"]) == index)
        #expect(try await git(root, ["diff"]) == work)
        #expect(try String(contentsOf: root.appendingPathComponent("new file.txt"), encoding: .utf8) == "untracked")
        #expect(try await store.load().scenes.first?.phase == .restored)
        await #expect(throws: (any Error).self) { try await service.restore(try #require(await store.load().scenes.first)) }
    }

    @Test("Scene refuses dirty targets and changed branch tips without overwriting files")
    func sceneGuards() async throws {
        let root = try await fixture(); defer { remove(root) }
        let service = WorkSceneService(store: ProjectToolsStore(root: root.appendingPathComponent(".git/tools")))
        try write("saved", "new.txt", root)
        let scene = try await service.save(name: "work", repository: root, draft: "", agentDraft: "", selectedPath: nil, goalID: nil, relatedURL: "", section: "changes")
        try write("keep", "new.txt", root)
        await #expect(throws: (any Error).self) { try await service.restore(scene) }
        #expect(try String(contentsOf: root.appendingPathComponent("new.txt"), encoding: .utf8) == "keep")
        _ = try await git(root, ["add", "."]); _ = try await git(root, ["commit", "-m", "moved"])
        await #expect(throws: (any Error).self) { try await service.restore(scene) }
    }

    @Test("Scenes can be restored in a separate worktree and deleted without dropping unrelated stashes")
    func sceneWorktree() async throws {
        let root = try await fixture(); let target = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer { remove(target); remove(root) }
        let store = ProjectToolsStore(root: root.appendingPathComponent(".git/tools")); let service = WorkSceneService(store: store)
        try write("saved", "new.txt", root)
        let scene = try await service.save(name: "copy", repository: root, draft: "", agentDraft: "", selectedPath: nil, goalID: nil, relatedURL: "", section: "changes")
        try await service.createWorktree(for: scene, at: target)
        #expect(try String(contentsOf: target.appendingPathComponent("new.txt"), encoding: .utf8) == "saved")
        try await service.rename(scene, name: "renamed"); #expect(try await store.load().scenes.first?.name == "renamed")
        try await service.delete(scene); #expect(try await store.load().scenes.isEmpty)
        #expect(!(try await git(root, ["stash", "list"])).isEmpty)
    }

    @Test("Ignore inspection identifies rule provenance, previews without writes and rejects stale saves")
    func ignoreRules() async throws {
        let root = try await fixture(); defer { remove(root) }
        let service = IgnoreRulesService()
        try write("generated", "build.log", root)
        var draft = try await service.load(repository: root, localOnly: false)
        draft.text = "*.log\n"
        let preview = try await service.preview(draft, repository: root)
        #expect(preview == ["+ build.log"])
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".gitignore").path))
        try await service.save(draft)
        let result = try await service.inspect("build.log", repository: root)
        #expect(result.ignored && result.pattern == "*.log" && result.line == "1" && !result.tracked)
        await #expect(throws: (any Error).self) { try await service.save(draft) }
        let tracked = try await service.inspect("base.txt", repository: root); #expect(tracked.tracked)
        try await service.stopTracking("base.txt", repository: root)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("base.txt").path))
    }

    @Test("Identity profiles use native repository includes, preserve unrelated config and reject mismatches")
    func identity() async throws {
        let root = try await fixture(); defer { remove(root) }
        let env = ["GIT_CONFIG_GLOBAL": root.appendingPathComponent(".git/test-global").path, "GIT_CONFIG_NOSYSTEM": "1"]
        let store = ProjectToolsStore(root: root.appendingPathComponent(".git/tools")); let service = RepositoryIdentityService(store: store, environment: env)
        let profile = RepositoryIdentityProfile(title: "Work", name: "Work Author", email: "work@example.test")
        _ = try await git(root, ["config", "test.keep", "untouched"])
        try await service.save(profile); try await service.bind(profile, to: root, directory: false, repository: root)
        let values = try await service.effective(repository: root)
        #expect(values.first { $0.key == "user.email" }?.value == profile.email)
        try await RepositoryIdentityService.verifyBinding(repository: root, environment: env)
        let config = root.appendingPathComponent(".git/config")
        try (String(contentsOf: config, encoding: .utf8) + "\n[user]\n email = wrong@example.test\n").write(to: config, atomically: true, encoding: .utf8)
        await #expect(throws: (any Error).self) { try await RepositoryIdentityService.verifyBinding(repository: root, environment: env) }
        #expect(try await git(root, ["config", "--get", "test.keep"]) == "untouched")
        let binding = try #require(await store.load().bindings.first)
        try await service.unbind(binding); try await service.delete(profile)
        #expect(try await store.load().profiles.isEmpty)
    }

    @Test("Directory identities do not change the active global author or an unrelated directory")
    func directoryIdentity() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { remove(parent) }
        let root = try await fixture(at: parent.appendingPathComponent("repo"))
        let store = ProjectToolsStore(root: parent.appendingPathComponent("tools"))
        let env = ["GIT_CONFIG_GLOBAL": parent.appendingPathComponent("global.gitconfig").path, "GIT_CONFIG_NOSYSTEM": "1"]
        let service = RepositoryIdentityService(store: store, environment: env)
        let profile = RepositoryIdentityProfile(title: "Folder", name: "Folder Author", email: "folder@example.test")
        try await service.save(profile)
        _ = try await git(root, ["config", "--unset", "user.name"]); _ = try await git(root, ["config", "--unset", "user.email"])
        try await service.bind(profile, to: parent, directory: true, repository: root)
        let effectiveEmail = try await service.effective(repository: root).first { $0.key == "user.email" }?.value
        #expect(effectiveEmail == profile.email)
        try await service.unbind(try #require(await store.load().bindings.first))
        #expect(try await service.effective(repository: root).first { $0.key == "user.email" }?.value == "")
    }

    @Test("Command discovery never executes project files and custom commands persist")
    func commands() async throws {
        let root = try await fixture(); defer { remove(root) }
        try write("{\"scripts\":{\"test\":\"touch MUST_NOT_EXIST\"},\"packageManager\":\"pnpm@9\"}", "package.json", root)
        try write("$(shell touch MUST_NOT_EXIST)\nbuild:\n\t@echo done\n", "Makefile", root)
        try write("// swift-tools-version: 6.1\n", "Package.swift", root)
        let commands = try await ProjectCommandDiscovery().discover(repository: root)
        #expect(commands.count == 5)
        #expect(commands.first { $0.title == "test" }?.executable == "pnpm")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("MUST_NOT_EXIST").path))
        let store = ProjectToolsStore(root: root.appendingPathComponent(".git/tools"))
        try await store.update { $0.commands = commands }
        #expect(try await store.load().commands == commands)
    }

    @Test("Command runner streams output, reports failures and stops only its owned group")
    func commandProcess() async throws {
        let root = try await fixture(); defer { remove(root) }
        var externalPID: pid_t = 0
        let externalArguments = [strdup("/bin/sleep"), strdup("30"), nil]
        defer { externalArguments.forEach { free($0) } }
        let spawnCode = externalArguments.withUnsafeBufferPointer { argv in
            posix_spawn(&externalPID, "/bin/sleep", nil, nil, UnsafeMutablePointer(mutating: argv.baseAddress!), nil)
        }
        #expect(spawnCode == 0)
        guard spawnCode == 0 else { return }
        defer {
            // The unreaped fixture PID stays owned until cleanup; avoid Foundation's run-loop wait in an async test.
            kill(externalPID, SIGKILL)
            var status: Int32 = 0
            while waitpid(externalPID, &status, 0) == -1 && errno == EINTR { }
        }
        let process = ProjectCommandProcess()
        let command = ProjectCommand(id: "run", title: "test", executable: "/bin/sh", arguments: ["-c", "printf 'ready\\n'; sleep 30 & wait"], repositoryPath: root.path)
        var output = ""; var stopped = false
        for await event in process.events(command: command) {
            switch event.kind {
            case .output(let value): output += value; if output.contains("ready") { process.stopAndWait() }
            case .stopped: stopped = true
            default: break
            }
        }
        var externalStatus = siginfo_t()
        #expect(waitid(P_PID, id_t(externalPID), &externalStatus, WEXITED | WNOHANG | WNOWAIT) == 0)
        #expect(output.contains("ready") && stopped && externalStatus.si_pid == 0)
        let failed = ProjectCommandProcess()
        var code: Int32?
        for await event in failed.events(command: ProjectCommand(id: "failed", title: "failed", executable: "/bin/sh", arguments: ["-c", "exit 7"], repositoryPath: root.path)) {
            if case .finished(let value) = event.kind { code = value }
        }
        #expect(code == 7)
        #expect(ProjectCommandOutput.localURL("http://localhost:3000/") != nil)
        #expect(ProjectCommandOutput.localURL("https://localhost.evil.test/") == nil)
        #expect(!ProjectCommandOutput.redact("token=fixture-only\n").contains("fixture-only"))
    }

    @MainActor @Test("New panels render populated, empty and error states, in narrow/wide and light/dark windows")
    func renderPanels() async throws {
        let root = try await fixture(); defer { remove(root) }
        let store = ProjectToolsStore(root: root.appendingPathComponent(".git/tools"))
        let tools = ProjectToolsViewModel(store: store)
        let workspace = WorkspaceViewModel(); workspace.appPreferences.monitoringEngineEnabled = false
        workspace.apply(RepositorySnapshot(rootURL: root, branchName: "main", upstreamName: nil, aheadCount: 0, behindCount: 0,
            changes: [], commits: [], branches: []))
        let output = ProcessInfo.processInfo.environment["GITGATTO_PROJECT_TOOLS_UI_OUTPUT"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let language = AppPreferencesStore.load().language
        defer { if output != nil { L10n.activate(language) } }
        for populated in (output == nil ? [true] : [false, true]) {
            if populated {
                let head = try await git(root, ["rev-parse", "HEAD"])
                var scene = WorkScene(name: "Feature / long working context — staged and unstaged changes", repositoryPath: root.path, branch: "main", head: head,
                    selectedPath: "base.txt", draft: "Commit draft", agentDraft: "Review the changes", goalID: nil, relatedURL: "https://example.test/issues/42", section: "changes")
                scene.phase = .saved
                let saved = scene
                let command = ProjectCommand(id: "fixture-run", title: "Development server / diagnostic output", executable: "/usr/bin/printf", arguments: ["http://localhost:3000/\\nDiagnostic fixture output\\n"], repositoryPath: root.path, timeoutSeconds: 5)
                let profile = RepositoryIdentityProfile(title: "Work / profile with a longer localized title", name: "Fixture Author", email: "fixture@example.test")
                try await store.update { $0.scenes = [saved]; $0.commands = [command]; $0.profiles = [profile] }
                tools.start(command)
                try await waitFor(tools.$runs.map { !$0.isEmpty && $0.allSatisfy { !$0.running } })
                tools.query.text = "baseline"; tools.search(repositories: [root])
                try await waitFor(tools.$searching.map { !$0 })
                if let match = tools.searchResult.matches.first {
                    tools.select(match)
                    try await waitFor(tools.$preview.map { !$0.isEmpty })
                }
            }
            await tools.load(repository: root)
            await tools.loadRules(repository: root, local: false)
            tools.error = populated ? nil : "Diagnostic fixture: " + String(repeating: "repository path / error details ", count: 10)
            for tool in ProjectTool.allCases {
                for width in (output == nil ? [700] : [560, 980]) {
                    for dark in (output == nil ? [false] : [false, true]) {
                        if output != nil { L10n.activate(width == 560 && dark ? .arabic : width == 980 ? .german : .simplifiedChinese) }
                        let content = ProjectToolsPanel(workspace: workspace, tools: tools, selection: tool)
                            .environment(\.colorScheme, dark ? .dark : .light)
                            .environment(\.locale, L10n.locale)
                            .environment(\.layoutDirection, width == 560 && dark ? .rightToLeft : .leftToRight)
                        let host = NSHostingView(rootView: content)
                        host.wantsLayer = true
                        let size = NSSize(width: width, height: 760)
                        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); window.contentView = host
                        host.frame = NSRect(origin: .zero, size: size); window.makeKeyAndOrderFront(nil)
                        await Task.yield()
                        await tools.load(repository: root, tool: tool)
                        await Task.yield()
                        if tool == .identities { try await waitFor(tools.$identityValues.map { $0.count == 5 }) }
                        if populated, tool == .commands { try await waitFor(tools.$commands.map { !$0.isEmpty }) }
                        await Task.yield(); host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                        #expect(abs(host.bounds.width - CGFloat(width)) < 1)
                        if populated, tool == .search {
                            let field = try #require(editableTextField(in: host))
                            #expect(window.makeFirstResponder(field))
                            #expect(window.firstResponder is NSTextView)
                        }
                        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        let data = try #require(bitmap.representation(using: .png, properties: [:]))
                        #expect(data.count > 1000)
                        if let output {
                            let name = "\(tool.rawValue)-\(width)-\(dark ? "dark" : "light")-\(populated ? "content" : "empty")"
                            try data.write(to: output.appendingPathComponent(name + ".png"))
                            let bottomURL = output.appendingPathComponent(name + "-bottom.png")
                            if FileManager.default.fileExists(atPath: bottomURL.path) { try FileManager.default.removeItem(at: bottomURL) }
                            if populated, tool == .identities, width == 560, let scroll = verticalScrollView(in: host), let document = scroll.documentView {
                                #expect(document.bounds.width <= scroll.contentView.bounds.width + 1)
                                let bottom = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
                                scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom)); scroll.reflectScrolledClipView(scroll.contentView)
                                await Task.yield(); host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                                CATransaction.flush()
                                let bottomBitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width), pixelsHigh: Int(host.bounds.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                                let context = try #require(NSGraphicsContext(bitmapImageRep: bottomBitmap))
                                let layer = try #require(host.layer)
                                context.cgContext.translateBy(x: 0, y: host.bounds.height)
                                context.cgContext.scaleBy(x: 1, y: -1)
                                layer.render(in: context.cgContext)
                                try #require(bottomBitmap.representation(using: .png, properties: [:])).write(to: bottomURL)
                            }
                        }
                        window.orderOut(nil); window.contentView = nil; window.close()
                    }
                }
            }
        }
    }

    @MainActor private func waitFor(_ publisher: some Publisher<Bool, Never>) async throws {
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        let subscription = publisher.sink { continuation.yield($0) }
        defer { subscription.cancel(); continuation.finish() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await ready in stream { if ready { return } }
                throw CancellationError()
            }
            group.addTask { try await Task.sleep(for: .seconds(30)); throw ProjectToolsError(key: "timeout") }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }

    @MainActor private func editableTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { editableTextField(in: $0) }.first
    }

    @MainActor private func verticalScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, let document = scroll.documentView, document.bounds.height > scroll.contentView.bounds.height { return scroll }
        return view.subviews.lazy.compactMap { verticalScrollView(in: $0) }.first
    }

    @Test("History filters include deleted files and never search secret paths")
    func historyFilters() async throws {
        let root = try await fixture(); defer { remove(root) }
        try write("historyneedle", "gone.swift", root)
        try write("secretneedle", ".env", root)
        _ = try await git(root, ["add", "."]); _ = try await git(root, ["commit", "-m", "add files"])
        _ = try await git(root, ["rm", "gone.swift"]); _ = try await git(root, ["commit", "-m", "remove file"])
        let service = ProjectCodeSearchService()
        var query = ProjectCodeQuery(); query.scope = .history; query.text = "historyneedle"; query.fileExtension = "swift"
        let historical = try await service.search(query, repositories: [root])
        #expect(historical.matches.count == 2)
        #expect(try await service.preview(#require(historical.matches.first)).contains("historyneedle"))
        query.text = "secretneedle"; query.fileExtension = ""
        #expect(try await service.search(query, repositories: [root]).matches.isEmpty)
        query.scope = .working; query.text = "\0"
        await #expect(throws: (any Error).self) { try await service.search(query, repositories: [root]) }
    }

    @Test("Ignore preview includes previously ignored files and local rule provenance")
    func ignoredFilePreview() async throws {
        let root = try await fixture(); defer { remove(root) }
        try write("*.log\n", ".gitignore", root); try write("ignored", "old.log", root)
        let service = IgnoreRulesService()
        var draft = try await service.load(repository: root, localOnly: false); draft.text = ""
        #expect(try await service.preview(draft, repository: root) == ["− old.log"])
        #expect(try String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8) == "*.log\n")
        var local = try await service.load(repository: root, localOnly: true); local.text = "local.tmp\n"
        try await service.save(local)
        let inspected = try await service.inspect("local.tmp", repository: root)
        #expect(inspected.source.hasSuffix("info/exclude") && inspected.ignored)
    }

    @Test("Interrupted scene saves can be recovered from the owned stash marker")
    func interruptedScene() async throws {
        let root = try await fixture(); defer { remove(root) }
        let store = ProjectToolsStore(root: root.appendingPathComponent(".git/tools")); let service = WorkSceneService(store: store)
        let head = try await git(root, ["rev-parse", "HEAD"])
        let pending = WorkScene(name: "interrupted", repositoryPath: root.path, branch: "main", head: head,
            selectedPath: nil, draft: "draft", agentDraft: "", goalID: nil, relatedURL: "", section: "changes")
        try await store.update { $0.scenes.append(pending) }
        try write("preserve", "untracked.txt", root)
        _ = try await git(root, ["stash", "push", "--include-untracked", "-m", pending.marker])
        try await service.recoverPending(pending)
        let recovered = try #require(await store.load().scenes.first)
        #expect(recovered.phase == .saved && recovered.stash != nil)
        try await service.restore(recovered)
        #expect(try String(contentsOf: root.appendingPathComponent("untracked.txt"), encoding: .utf8) == "preserve")
        let before = try await git(root, ["status", "--porcelain"])
        var interrupted = pending; interrupted.id = UUID()
        let unfinished = interrupted
        try await store.update { $0.scenes.append(unfinished) }
        try await service.acknowledge(unfinished)
        #expect(try await store.load().scenes.last?.phase == .handled)
        #expect(try await git(root, ["status", "--porcelain"]) == before)
        await #expect(throws: (any Error).self) { try await service.acknowledge(unfinished) }
        await #expect(throws: (any Error).self) { try await service.recoverPending(pending) }
    }

    @Test("Identity guard detects environment overrides and accepts equivalent Git boolean values")
    func identityEnvironment() async throws {
        let root = try await fixture(); defer { remove(root) }
        let env = ["GIT_CONFIG_GLOBAL": root.appendingPathComponent(".git/test-global").path, "GIT_CONFIG_NOSYSTEM": "1"]
        let store = ProjectToolsStore(root: root.appendingPathComponent(".git/tools")); let service = RepositoryIdentityService(store: store, environment: env)
        let profile = RepositoryIdentityProfile(title: "Work", name: "Work Author", email: "work@example.test")
        try await service.save(profile); try await service.bind(profile, to: root, directory: false, repository: root)
        let config = root.appendingPathComponent(".git/config")
        let original = try String(contentsOf: config, encoding: .utf8)
        try (original + "\n[commit]\n gpgsign = off\n").write(to: config, atomically: true, encoding: .utf8)
        try await RepositoryIdentityService.verifyBinding(repository: root, environment: env)
        var overrides = env; overrides["GIT_AUTHOR_EMAIL"] = "wrong@example.test"
        await #expect(throws: (any Error).self) { try await RepositoryIdentityService.verifyBinding(repository: root, environment: overrides) }
    }

    @Test("Command deadlines, argv boundaries and multiline secret filtering")
    func commandBoundaries() async throws {
        let root = try await fixture(); defer { remove(root) }
        let runner = ProjectCommandProcess(); var failed = false
        let command = ProjectCommand(id: "timeout", title: "timeout", executable: "/bin/sleep", arguments: ["30"], repositoryPath: root.path, timeoutSeconds: 1)
        let start = Date()
        for await event in runner.events(command: command) { if case .failed = event.kind { failed = true } }
        #expect(failed && Date().timeIntervalSince(start) < 6)
        let argv = ProjectCommandProcess(); var output = ""
        let literal = "; touch MUST_NOT_EXIST"
        for await event in argv.events(command: ProjectCommand(id: "literal", title: "literal", executable: "/usr/bin/printf", arguments: ["%s", literal], repositoryPath: root.path)) {
            if case .output(let value) = event.kind { output += value }
        }
        #expect(output.contains(literal) && !FileManager.default.fileExists(atPath: root.appendingPathComponent("MUST_NOT_EXIST").path))
        var filter = ProjectCommandLogFilter()
        let filtered = filter.consume("-----BEGIN PRIVATE KEY-----\n") + filter.consume("SYNTHETIC-PRIVATE-CONTENT\n") + filter.consume("-----END PRIVATE KEY-----\n") + filter.consume("finished\n")
        #expect(!filtered.contains("SYNTHETIC") && filtered.contains("finished"))
        #expect(!ProjectCommandOutput.redact("{\"token\":\"SYNTHETIC-TOKEN\"}").contains("SYNTHETIC-TOKEN"))
    }

    @MainActor @Test("Concurrent panel reads complete, command pins remain discoverable and resources exist")
    func panelLoading() async throws {
        let root = try await fixture(); defer { remove(root) }
        try write("{\"scripts\":{\"test\":\"echo test\"}}", "package.json", root)
        let store = ProjectToolsStore(root: root.appendingPathComponent(".git/tools")); let tools = ProjectToolsViewModel(store: store)
        async let load: Void = tools.load(repository: root)
        async let rules: Void = tools.loadRules(repository: root, local: false)
        _ = await (load, rules)
        #expect(tools.ruleDraft != nil && tools.commands.count == 1)
        let command = try #require(tools.commands.first)
        try await tools.pin(command); try await tools.unpin(command)
        #expect(tools.commands.count == 1 && tools.state.commands.isEmpty)
        try write("invalid package json", "package.json", root)
        tools.error = nil
        await tools.load(repository: root, tool: .identities)
        #expect(tools.error == nil && !tools.identityValues.isEmpty)
        await tools.load(repository: root, tool: .commands)
        #expect(tools.error != nil && tools.commands.isEmpty)
        for tool in ProjectTool.allCases {
            let name = GattoIconAssets.assetName(for: tool.symbol)
            #expect(AppResourceBundle.current.url(forResource: name, withExtension: "svg") != nil || AppResourceBundle.current.url(forResource: name, withExtension: "svg", subdirectory: "UIIcons") != nil)
        }
    }

    private func fixture(at location: URL? = nil) async throws -> URL {
        let root = location ?? FileManager.default.temporaryDirectory.appendingPathComponent("gitgatto-tools-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try await git(root, ["init", "-q", "-b", "main"])
        _ = try await git(root, ["config", "user.name", "Fixture"]); _ = try await git(root, ["config", "user.email", "fixture@example.test"])
        _ = try await git(root, ["config", "commit.gpgsign", "false"])
        try write("baseline\n", "base.txt", root)
        _ = try await git(root, ["add", "."]); _ = try await git(root, ["commit", "-m", "baseline"])
        return root
    }
    private func git(_ root: URL, _ args: [String]) async throws -> String { try await ProjectToolsPolicy.text(root, args) }
    private func write(_ text: String, _ path: String, _ root: URL) throws { try Data(text.utf8).write(to: root.appendingPathComponent(path)) }
    private func remove(_ root: URL) { try? FileManager.default.removeItem(at: root) }
}
