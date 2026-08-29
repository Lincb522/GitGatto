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

        #expect(professional.contains("Three to five concise capability groups"))
        #expect(professional.contains("distinctive subsystem"))
        #expect(minimal.contains("smallest complete project page"))
        #expect(minimal.contains("Avoid walkthroughs, feature-card grids"))
        #expect(openSource.contains("for users first and contributors second"))
        #expect(openSource.contains("only the commands contributors must run"))
        #expect(product.contains("based on user outcomes"))
        #expect(product.contains("Omit unnecessary walkthroughs"))
        #expect(Set([professional, minimal, openSource, product]).count == ReadmeAgentStyle.allCases.count)
    }

    @Test("README templates remove repeated and obvious explanation", arguments: ReadmeAgentStyle.allCases)
    func keepsReadmeCopyConcise(style: ReadmeAgentStyle) {
        let prompt = GitAgentProfile.readmePrompt(style: style)

        #expect(prompt.contains("Preserve concrete implemented capabilities"))
        #expect(prompt.contains("it does not mean minimizing section count"))
        #expect(prompt.contains("State each fact once"))
        #expect(prompt.contains("Do not explain obvious controls"))
        #expect(prompt.contains("Do not create a section only because"))
        #expect(prompt.contains("keep every unique verified capability"))
        #expect(prompt.contains("exact current slogan"))
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
