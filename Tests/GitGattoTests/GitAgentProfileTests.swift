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
    }

    @Test("Keeps remote writes behind explicit app controls")
    func keepsRemoteWriteBoundary() {
        #expect(GitAgentProfile.remoteBoundary.contains("Do not push"))
        #expect(GitAgentProfile.remoteBoundary.contains("publish comments"))
        #expect(GitAgentProfile.permission(for: .analyze).contains("without modifying"))
    }
}
