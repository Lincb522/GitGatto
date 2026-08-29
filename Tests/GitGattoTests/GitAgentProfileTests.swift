import Foundation
import Testing
@testable import GitGatto

@Suite("Git and GitHub Agent profile")
struct GitAgentProfileTests {
    @Test("Includes repository and GitHub inspection skills")
    func includesProfessionalGitSkills() {
        #expect(GitAgentProfile.core.contains("git status"))
        #expect(GitAgentProfile.core.contains("git diff"))
        #expect(GitAgentProfile.core.contains("gh pr"))
        #expect(GitAgentProfile.core.contains("GitHub Actions"))
        #expect(GitAgentProfile.core.contains("Git LFS"))
        #expect(GitAgentProfile.core.contains("submodules"))
        #expect(GitAgentProfile.core.contains("worktrees"))
        #expect(GitAgentSkill.allCases.count == 9)
    }

    @Test("Keeps remote writes behind explicit app controls")
    func keepsRemoteWriteBoundary() {
        #expect(GitAgentProfile.remoteBoundary.contains("Do not push"))
        #expect(GitAgentProfile.remoteBoundary.contains("publish comments"))
        #expect(GitAgentProfile.permission(for: .analyze).contains("without modifying"))
    }

    @Test("Routes representative Git failures to focused repair skills", arguments: [
        ("Permission denied (publickey)", GitAgentRepairRoute.authentication),
        ("rejected non-fast-forward", GitAgentRepairRoute.synchronization),
        ("CONFLICT (content): Merge conflict", GitAgentRepairRoute.conflicts),
        ("error: gpg failed to sign the data", GitAgentRepairRoute.hooksAndSigning),
        ("git-lfs was not found on your PATH", GitAgentRepairRoute.largeFiles),
        ("No url found for submodule path", GitAgentRepairRoute.submodules),
        ("Unable to create .git/index.lock", GitAgentRepairRoute.locksAndPermissions),
        ("branch is already checked out at worktree", GitAgentRepairRoute.worktrees)
    ])
    func routesGitFailure(message: String, expected: GitAgentRepairRoute) {
        let report = GlobalErrorHandler.report(
            for: GitCommandError(arguments: ["commit"], exitCode: 1, message: message),
            context: .git(.commit),
            repositoryURL: URL(fileURLWithPath: "/tmp/example", isDirectory: true)
        )

        #expect(GitAgentProfile.repairRoute(for: report) == expected)
    }

    @Test("Builds a bounded error repair request from the sanitized report")
    func buildsErrorRepairPrompt() {
        let report = GlobalErrorHandler.report(
            for: GitCommandError(
                arguments: ["push"],
                exitCode: 1,
                message: "remote rejected the update"
            ),
            context: .git(.push),
            repositoryURL: URL(fileURLWithPath: "/tmp/example", isDirectory: true)
        )

        let prompt = GitAgentProfile.errorResolutionPrompt(for: report)
        #expect(prompt.contains("GG-GIT-PUSH-1"))
        #expect(prompt.contains("git push"))
        #expect(prompt.contains("Do not repeat pull, push, fetch"))
        #expect(prompt.contains("Do not change global Git configuration"))
    }

    @Test("README templates require evidence-backed layout and stack identifiers", arguments: ReadmeAgentStyle.allCases)
    func buildsDeepReadmeRewritePrompt(style: ReadmeAgentStyle) {
        let prompt = GitAgentProfile.readmePrompt(style: style)

        #expect(prompt.contains("GitHub-Flavored Markdown"))
        #expect(prompt.contains("technology-stack identifiers"))
        #expect(prompt.contains("manifests, lockfiles, imports"))
        #expect(prompt.contains("Do not generate, redraw, rename, or relocate assets"))
        #expect(prompt.contains("Do not present contributor-only project generators"))
        #expect(prompt.contains("narrow-layout readability"))
    }

    @Test("README templates preserve distinct document structures")
    func keepsReadmeTemplateStructuresDistinct() {
        let professional = GitAgentProfile.readmePrompt(style: .professional)
        let minimal = GitAgentProfile.readmePrompt(style: .minimal)
        let openSource = GitAgentProfile.readmePrompt(style: .openSource)
        let product = GitAgentProfile.readmePrompt(style: .product)

        #expect(professional.contains("two-column capability matrix"))
        #expect(professional.contains("compact section navigator"))
        #expect(minimal.contains("smallest complete project page"))
        #expect(minimal.contains("Avoid feature-card grids"))
        #expect(openSource.contains("for both users and contributors"))
        #expect(openSource.contains("only the test commands contributors are required to run"))
        #expect(product.contains("outcome-based capability grid"))
        #expect(product.contains("omit testimonials"))
        #expect(Set([professional, minimal, openSource, product]).count == ReadmeAgentStyle.allCases.count)
    }

    @Test("Localizes every built-in Git Agent skill", arguments: ["en", "zh-Hans"])
    func localizesSkills(language: String) {
        let bundle = L10n.bundle(preferredLanguages: [language])

        for skill in GitAgentSkill.allCases {
            let title = bundle.localizedString(forKey: skill.titleKey, value: skill.titleKey, table: nil)
            #expect(title != skill.titleKey)
            #expect(!title.isEmpty)
        }
    }
}
