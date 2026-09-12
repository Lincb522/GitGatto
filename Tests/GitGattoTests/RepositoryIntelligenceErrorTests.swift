import AppKit
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Intelligence error localization", .serialized)
@MainActor
struct RepositoryIntelligenceErrorTests {
    private var revisionError: GitCommandError {
        GitCommandError(arguments: ["show", "HEAD"], exitCode: 128,
                        message: "fatal: ambiguous argument 'HEAD': unknown revision or path not in the working tree.")
    }

    @Test("All languages classify Git errors without losing diagnostics or native validation")
    func diagnoses() throws {
        defer { L10n.activate(AppPreferencesStore.load().language) }
        for language in AppLanguage.allCases where language != .system {
            L10n.activate(language)
            for tab in RepositoryIntelligenceTab.allCases {
                let report = GlobalErrorHandler.report(for: revisionError, context: .intelligence(tab))
                #expect(report.explanation == L10n.text("error.explanation.git_revision"))
                #expect(report.explanation != report.message)
                #expect(report.exitCode == 128 && report.command == "git show")
                #expect(report.operation == L10n.text(tab.titleKey))
                #expect(report.diagnosticText.contains(revisionError.message))
            }
            let errors: [any Error] = [ChangeIntentError.repositoryChanged, ChangeIntentError.selectionDependency,
                ChangeIntentError.invalidPlan(L10n.text("intelligence.intent.error.status")),
                CodeProvenanceError.invalidLine, ReproductionCapsuleError.checksumMismatch]
            for error in errors {
                let report = GlobalErrorHandler.report(for: error, context: .intelligence(.intent))
                #expect(report.explanation == error.localizedDescription)
            }
            for (error, key) in [(ChangeIntentError.verificationFailed(command: "test", output: "synthetic raw log"), "intelligence_verification"),
                                 (.rollbackFailed("synthetic raw failure", "synthetic recovery log"), "intelligence_rollback")] {
                let report = GlobalErrorHandler.report(for: error, context: .intelligence(.intent))
                #expect(report.explanation == L10n.text("error.explanation." + key))
                #expect(!report.explanation.contains("synthetic"))
                #expect(report.message.contains("synthetic"))
                #expect(!report.explanation.hasPrefix("error."))
                #expect(!report.recoverySuggestion.hasPrefix("error."))
            }
            let unknown = GlobalErrorHandler.report(for: NSError(domain: "fixture", code: 9,
                userInfo: [NSLocalizedDescriptionKey: "untranslated remote output"]), context: .intelligence(.capsules))
            #expect(unknown.explanation == L10n.format("error.dialog.operation_title", L10n.text(RepositoryIntelligenceTab.capsules.titleKey)))
            #expect(unknown.recoverySuggestion == L10n.text("error.recovery.intelligence"))
            #expect(unknown.message == "untranslated remote output")
        }
        let secret = "ghp_syntheticFixtureOnly"
        let redacted = GlobalErrorHandler.report(for: ChangeIntentError.unsupportedChange(secret), context: .intelligence(.intent))
        #expect(!redacted.diagnosticText.contains(secret))
        #expect(!redacted.explanation.contains(secret))
    }

    @Test("Every intelligence lane routes service failures through the shared catalog")
    func viewModelRoutes() async throws {
        defer { L10n.activate(AppPreferencesStore.load().language) }
        L10n.activate(.simplifiedChinese)
        let services = FailingIntelligenceServices(error: revisionError)
        let model = RepositoryIntelligenceViewModel(intentService: services, provenanceService: services,
            capsuleService: services, activityLedger: services)
        let repository = URL(fileURLWithPath: "/tmp/intelligence-error-fixture")
        model.load(repositoryURL: repository)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.intentError == nil || model.capsuleError == nil {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        model.provenancePath = "example.swift"
        await model.traceProvenance()
        await model.clearActivity()
        for report in [model.intentError, model.provenanceError, model.capsuleError, model.activityError] {
            let report = try #require(report)
            #expect(report.explanation == L10n.text("error.explanation.git_revision"))
            #expect(report.message == revisionError.message)
            #expect(report.repositoryPath == repository.path)
        }
        model.provenanceLine = "invalid"
        await model.traceProvenance()
        #expect(model.provenanceError?.explanation == CodeProvenanceError.invalidLine.localizedDescription)
    }

    @Test("Localized errors and long summaries fit narrow, wide and RTL windows")
    func renderedErrors() async throws {
        defer { L10n.activate(AppPreferencesStore.load().language) }
        for (width, language, scheme) in [(320.0, AppLanguage.simplifiedChinese, ColorScheme.light),
                                          (860.0, .german, .dark), (320.0, .arabic, .dark)] {
            L10n.activate(language)
            for longContent in [false, true] {
                let error: any Error = longContent
                    ? ChangeIntentError.unsupportedChange(String(repeating: "Sources/VeryLongDirectoryName/", count: 80))
                    : revisionError
                let report = GlobalErrorHandler.report(for: error, context: .intelligence(.intent))
                let content = IntelligenceErrorState(report: report) {}
                    .environment(\.locale, L10n.locale)
                    .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
                    .environment(\.colorScheme, scheme)
                    .dynamicTypeSize(.accessibility1)
                    .background(AppPalette(scheme).background)
                let host = NSHostingView(rootView: content)
                let bounds = NSRect(x: 0, y: 0, width: width, height: 360)
                let window = NSWindow(contentRect: bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host
                host.frame = bounds
                defer { window.contentView = nil; window.close() }
                await Task.yield()
                host.layoutSubtreeIfNeeded()
                let scroll = try #require(descendants(host).compactMap { $0 as? NSScrollView }.first)
                let document = try #require(scroll.documentView)
                #expect(document.bounds.width <= scroll.contentView.bounds.width + 2)
                if longContent {
                    #expect(document.bounds.height > scroll.contentView.bounds.height)
                    document.scrollToVisible(NSRect(x: 0, y: document.bounds.maxY - 1, width: 1, height: 1))
                    host.layoutSubtreeIfNeeded()
                    #expect(scroll.documentVisibleRect.maxY >= document.bounds.maxY - 2)
                }
                let detailsLabel = try #require(descendants(host).compactMap { $0 as? NSTextField }
                    .first { $0.stringValue == L10n.text("error.section.details") })
                let visibleFrame = host.convert(detailsLabel.bounds, from: detailsLabel)
                #expect(host.bounds.intersects(visibleFrame))
                try capture(host, name: "error-\(language.rawValue)-\(longContent ? "long-summary-bottom" : "collapsed")")
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func capture<V: View>(_ host: NSHostingView<V>, name: String) throws {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(data.count > 2_000)
        if let path = ProcessInfo.processInfo.environment["GITGATTO_ERROR_SNAPSHOTS"] {
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(name + ".png"))
        }
    }
}

private actor FailingIntelligenceServices: ChangeIntentServing, CodeProvenanceServing, ReproductionCapsuleServing, RepositoryActivityLedgerServing {
    let error: GitCommandError
    init(error: GitCommandError) { self.error = error }
    func makePlan(in repositoryURL: URL, selection: ChangeIntentSelection?) throws -> ChangeIntentPlan { throw error }
    func apply(_ plan: ChangeIntentPlan, verificationCommand: String?, in repositoryURL: URL) throws -> ChangeIntentApplyResult { throw error }
    func trace(filePath: String, line: Int, in repositoryURL: URL) throws -> CodeProvenanceReport { throw error }
    func trace(commitHash: String, filePath: String, line: Int, in repositoryURL: URL) throws -> CodeProvenanceReport { throw error }
    func capsules() throws -> [ReproductionCapsule] { throw error }
    func export(from repositoryURL: URL, failingCommand: String?, failureOutput: String?, to destinationURL: URL) throws -> ReproductionCapsule { throw error }
    func importArchive(at archiveURL: URL) throws -> ReproductionCapsule { throw error }
    func restore(_ capsule: ReproductionCapsule, in repositoryURL: URL) throws -> URL { throw error }
    func delete(_ capsule: ReproductionCapsule) throws { throw error }
    func seed(_ repositoryURLs: [URL]) {}
    func recordChange(in repositoryURL: URL) {}
    func events(for repositoryURL: URL) -> [RepositoryActivityEvent] { [] }
    func clearEvents(for repositoryURL: URL) throws { throw error }
}
