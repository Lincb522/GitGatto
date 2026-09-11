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

    @Test("Natural-language search prompt embeds the user request verbatim")
    func searchPromptEmbedsRequest() {
        let request = "Swift Git clients for macOS with more than 500 stars"
        let prompt = CodexService.gitHubSearchQueryPrompt(request, scope: .projects)

        #expect(prompt.contains("GitHub repository search"))
        #expect(prompt.hasSuffix("Request:\n\(request)"))
        #expect(!prompt.contains("input.prefix"))

        let developerPrompt = CodexService.gitHubSearchQueryPrompt("Rust maintainers", scope: .developers)
        #expect(developerPrompt.contains("GitHub user search"))
        #expect(developerPrompt.hasSuffix("Request:\nRust maintainers"))
    }

    @Test("Natural-language search prompt truncates oversized requests")
    func searchPromptTruncatesRequest() {
        let request = String(repeating: "a", count: 1_500)
        let prompt = CodexService.gitHubSearchQueryPrompt(request, scope: .projects)

        #expect(prompt.hasSuffix(String(repeating: "a", count: 1_000)))
        #expect(!prompt.hasSuffix(String(repeating: "a", count: 1_001)))
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

@Suite("Document translation response integrity")
struct DocumentTranslationIntegrityTests {
    @Test("Markdown translation retains code indentation and headings", arguments: [AIOutputFormat.plainText, .codexJSONL])
    func preservesMarkdownFormatting(format: AIOutputFormat) async throws {
        let source = "# Guide\n\nRun this example:\n\n```python\ndef answer():\n    # Keep this comment\n    return 42\n```\n"
        let translation = "# 指南\n\n运行这个示例：\n\n```python\ndef answer():\n    # Keep this comment\n    return 42\n```\n"
        try await withCLI(response: translation, format: format) { service in
            let result = try await service.translateMarkdown(source, target: .simplifiedChinese)
            #expect(result == translation)
        }
    }

    @Test("HTML translation accepts unchanged URLs and equivalent entities")
    func restoresHTMLTranslation() async throws {
        let response = #"{"translations":["请参阅 https://example.invalid/docs，然后重启。","命令 &#38; 示例"]}"#
        try await withCLI(response: response) { service in
            let result = try await service.translateHTML(
                "<article><p>Read https://example.invalid/docs, then restart.</p><p>Commands &amp; examples</p><pre><code>  npm install</code></pre></article>",
                target: .simplifiedChinese
            )
            #expect(result == "<article><p>请参阅 https://example.invalid/docs，然后重启。</p><p>命令 &#38; 示例</p><pre><code>  npm install</code></pre></article>")
        }
    }

    @Test("Only fragments that changed protected values are retried")
    func repairsChangedFragments() async throws {
        let response = #"{"translations":["安装指南","于 2026 年 9 月 5 日生效。","如果你是 GitHub 员工，请阅读指南。"]}"#
        let repaired = #"{"translations":["于 2026 年九月 5 日生效。","如果你是内部员工，请阅读指南。"]}"#
        try await withCLI(response: response, repairResponse: repaired, expectedCalls: 2) { service in
            let result = try await service.translateHTML(
                "<h1>Installation guide</h1><p>Effective September 5, 2026.</p><p>If you are a hubber, read the guide.</p>",
                target: .simplifiedChinese
            )
            #expect(result == "<h1>安装指南</h1><p>于 2026 年九月 5 日生效。</p><p>如果你是内部员工，请阅读指南。</p>")
        }
    }

    @Test("Protected content repair stops after one retry")
    func boundsRepairAttempts() async throws {
        let response = #"{"translations":["Visit https://other.invalid/docs"]}"#
        try await withCLI(response: response, expectedCalls: 2) { service in
            await #expect(throws: CodexServiceError.self) {
                try await service.translateHTML("<p>Visit https://example.invalid/docs</p>", target: .simplifiedChinese)
            }
        }
    }

    @Test("Markdown validation retries once without dropping code or formatting")
    func repairsMarkdownProtectedValues() async throws {
        let source = "# Guide\n\nEffective September 5, 2026.\n\n```sh\n  echo ready\n```\n"
        let response = "# 指南\n\n于 2026 年 9 月 5 日生效。\n\n```sh\n  echo ready\n```\n"
        let repaired = "# 指南\n\n于 2026 年九月 5 日生效。\n\n```sh\n  echo ready\n```\n"
        try await withCLI(response: response, repairResponse: repaired, expectedCalls: 2) { service in
            let result = try await service.translateMarkdown(source, target: .simplifiedChinese)
            #expect(result == repaired)
        }
    }

    @Test("Markdown still fails when the retry changes a protected URL")
    func boundsMarkdownRepairAttempts() async throws {
        try await withCLI(response: "See https://other.invalid/docs", expectedCalls: 2) { service in
            await #expect(throws: CodexServiceError.self) {
                try await service.translateMarkdown("See https://example.invalid/docs", target: .simplifiedChinese)
            }
        }
    }

    @Test("Malformed, missing and changed translation content is still rejected", arguments: [
        #"{"translations":["访问 https://other.invalid/docs。"]}"#,
        #"{"translations":[]}"#,
        #"{"translations":[""]}"#,
        #"{"translations":["访问 https://example.invalid/docs。","多余段落"]}"#,
        #"{"translations":["truncated""#,
    ])
    func rejectsInvalidHTMLTranslation(response: String) async throws {
        try await withCLI(response: response) { service in
            await #expect(throws: CodexServiceError.self) {
                try await service.translateHTML("<p>Visit https://example.invalid/docs.</p>", target: .simplifiedChinese)
            }
        }
    }

    private func withCLI(
        response: String,
        format: AIOutputFormat = .plainText,
        repairResponse: String? = nil,
        expectedCalls: Int? = nil,
        operation: (CodexService) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GitGatto-translation-integrity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let responseURL = directory.appendingPathComponent("response")
        let data: Data
        switch format {
        case .plainText:
            data = Data(response.utf8)
        case .codexJSONL:
            data = try JSONSerialization.data(withJSONObject: [
                "type": "item.completed", "item": ["type": "agent_message", "text": response]
            ])
        }
        try data.write(to: responseURL)
        let repairedURL = directory.appendingPathComponent("repaired-response")
        try (repairResponse.map { Data($0.utf8) } ?? data).write(to: repairedURL)
        let callsURL = directory.appendingPathComponent("calls")
        let executable = directory.appendingPathComponent("translation-cli")
        try """
        #!/bin/sh
        cat >/dev/null
        if [ -f '\(callsURL.path)' ]; then
            printf x >> '\(callsURL.path)'
            exec /bin/cat '\(repairedURL.path)'
        fi
        printf x > '\(callsURL.path)'
        exec /bin/cat '\(responseURL.path)'

        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        var configured = AIProviderConfiguration.preset(.custom)
        configured.executable = executable.path
        configured.versionArguments = ""
        configured.translationArguments = ""
        configured.outputFormat = format
        let configuration = configured
        let service = CodexService(lane: .translation, configurationSource: { _ in configuration })
        try await operation(service)
        if let expectedCalls {
            #expect(try Data(contentsOf: callsURL).count == expectedCalls)
        }
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

    @Test("Renews the timeout for each document translation batch")
    func renewsTranslationTimeoutPerBatch() async throws {
        let previousTranslation = AIProviderSettings.load(.translation)
        defer { AIProviderSettings.save(previousTranslation, lane: .translation) }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGatto-translation-timeout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("translation-cli")
        let script = #"""
        #!/bin/sh
        cat >/dev/null
        sleep 3
        if [ -f "$0.state" ]; then
            printf '{"translations":["translated"]}\n'
        else
            : > "$0.state"
            printf '{"translations":["translated","translated","translated","translated","translated"]}\n'
        fi
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        var configuration = AIProviderConfiguration.preset(.custom)
        configuration.executable = executable.path
        configuration.versionArguments = ""
        configuration.translationArguments = ""
        AIProviderSettings.save(configuration, lane: .translation)

        let service = CodexService(lane: .translation, translationRunTimeout: .seconds(10))
        let source = "<article><p>\(String(repeating: "a", count: 36_000))</p></article>"
        let translated = try await service.translateHTML(source, target: .simplifiedChinese)

        #expect(translated.contains("translated"))
        #expect(!translated.contains("aaaa"))
    }
}
