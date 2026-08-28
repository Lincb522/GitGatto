import Foundation
import Testing
@testable import GitGatto

@Suite("Codex JSONL parser")
struct CodexJSONLParserTests {
    @Test("Builds configurable CLI arguments without a shell")
    func buildsConfiguredArguments() {
        var configuration = AIProviderConfiguration.preset(.custom)
        configuration.analyzeArguments = "run\n--directory\n{repository}\n--prompt\n{prompt}\n--empty\n{empty}"

        #expect(configuration.arguments(for: .project, mode: .analyze) == [
            "run", "--directory", "{repository}", "--prompt", "{prompt}", "--empty", ""
        ])
    }

    @Test("Returns the final message and completed action counts")
    func parsesCompletedItems() throws {
        let jsonl = """
        {"type":"thread.started","thread_id":"thread-1"}
        {"type":"item.completed","item":{"id":"item-1","type":"command_execution","command":"git status","status":"completed"}}
        {"type":"item.completed","item":{"id":"item-2","type":"file_change","changes":[{"path":"Sources/App.swift","kind":"update"}]}}
        {"type":"item.completed","item":{"id":"item-3","type":"agent_message","text":"First draft"}}
        {"type":"item.completed","item":{"id":"item-4","type":"agent_message","text":"Repository is ready."}}
        {"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":4}}
        """

        let result = try CodexJSONLParser.parse(Data(jsonl.utf8))

        #expect(result.response == "Repository is ready.")
        #expect(result.commandCount == 1)
        #expect(result.fileChangeCount == 1)
        #expect(result.events == [
            CodexOperationEvent(kind: .command, summary: "git status"),
            CodexOperationEvent(kind: .fileChange, summary: "update · Sources/App.swift")
        ])
    }

    @Test("Rejects a run without a final agent message")
    func requiresResponse() {
        let jsonl = """
        {"type":"thread.started","thread_id":"thread-1"}
        {"type":"turn.completed","usage":{"input_tokens":2,"output_tokens":0}}
        """

        #expect(throws: CodexServiceError.self) {
            try CodexJSONLParser.parse(Data(jsonl.utf8))
        }
    }

    @Test("Removes documentation-style heading markers")
    func cleansHeadings() {
        let text = """
        ### Result


        Updated the branch.
        ## Next step
        Push when ready.
        """

        let result = CodexResponseFormatter.clean(text)

        #expect(result == "Result\n\nUpdated the branch.\nNext step\nPush when ready.")
        #expect(!result.contains("###"))
    }

    @Test("Translates README prose without exposing or changing HTML assets and code")
    func protectsHTMLDuringTranslation() throws {
        let html = """
        <h1>Project guide</h1>
        <img src="data:image/png;base64,PRIVATE_IMAGE_DATA" alt="Logo">
        <p>Install the application.</p>
        <pre><code>swift run GitGatto</code></pre>
        """
        let plan = HTMLTextTranslationPlan(html: html)

        #expect(plan.segments.map(\.text) == ["Project guide", "Install the application."])
        #expect(plan.characterCount == 37)
        #expect(plan.batches(maxCharacterCount: 20).count == 2)

        let restored = try #require(plan.restoring(["项目指南", "安装应用。"]))

        #expect(restored.contains("<h1>项目指南</h1>"))
        #expect(restored.contains("data:image/png;base64,PRIVATE_IMAGE_DATA"))
        #expect(restored.contains("<pre><code>swift run GitGatto</code></pre>"))
        #expect(plan.restoring([""]) == nil)
    }

    @Test("Groups long document prose into bounded translation batches")
    func batchesLongHTMLProse() {
        let prose = String(repeating: "Project documentation sentence. ", count: 2_500)
        let plan = HTMLTextTranslationPlan(html: "<article><p>\(prose)</p></article>")
        let batches = plan.batches(maxCharacterCount: 32_000)

        #expect(batches.count == 3)
        #expect(batches.flatMap { $0 } == Array(plan.segments.indices))
        #expect(batches.allSatisfy { batch in
            batch.reduce(0) { $0 + plan.segments[$1].text.count } <= 32_000
        })
    }
}

@Suite("Independent Agent CLI lanes", .serialized)
struct IndependentAILaneTests {
    @Test("Translation remains available while a project CLI is running")
    func runsProjectAndTranslationSeparately() async throws {
        let previousProject = AIProviderSettings.load(.project)
        let previousTranslation = AIProviderSettings.load(.translation)
        defer {
            AIProviderSettings.save(previousProject, lane: .project)
            AIProviderSettings.save(previousTranslation, lane: .translation)
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGatto-Agent-lanes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let started = directory.appendingPathComponent("project-started")
        let release = directory.appendingPathComponent("project-release")
        let completed = directory.appendingPathComponent("project-completed")
        let projectExecutable = directory.appendingPathComponent("project-cli")
        let translationExecutable = directory.appendingPathComponent("translation-cli")
        try "#!/bin/sh\ntouch '\(started.path)'\nwhile [ ! -f '\(release.path)' ]; do sleep 0.02; done\ntouch '\(completed.path)'\nprintf project-complete\n"
            .write(to: projectExecutable, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nprintf translation-complete\n"
            .write(to: translationExecutable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: projectExecutable.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: translationExecutable.path)

        var projectConfiguration = AIProviderConfiguration.preset(.custom)
        projectConfiguration.executable = projectExecutable.path
        projectConfiguration.versionArguments = ""
        projectConfiguration.analyzeArguments = ""
        var translationConfiguration = AIProviderConfiguration.preset(.custom)
        translationConfiguration.executable = translationExecutable.path
        translationConfiguration.versionArguments = ""
        translationConfiguration.translationArguments = ""
        AIProviderSettings.save(projectConfiguration, lane: .project)
        AIProviderSettings.save(translationConfiguration, lane: .translation)

        let projectService = CodexService(lane: .project)
        let translationService = CodexService(lane: .translation)
        let projectTask = Task {
            try await projectService.run(
                prompt: "Inspect this repository",
                context: [],
                in: directory,
                mode: .analyze
            )
        }
        defer { _ = FileManager.default.createFile(atPath: release.path, contents: Data()) }

        for _ in 0..<250 where !FileManager.default.fileExists(atPath: started.path) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(FileManager.default.fileExists(atPath: started.path))

        let translation = try await translationService.translate("hello", target: .simplifiedChinese)
        #expect(!FileManager.default.fileExists(atPath: completed.path))
        _ = FileManager.default.createFile(atPath: release.path, contents: Data())
        let project = try await projectTask.value

        #expect(translation == "translation-complete")
        #expect(project.response == "project-complete")
        #expect(FileManager.default.fileExists(atPath: completed.path))
    }
}
