import Foundation
import Testing
@testable import GitGatto

@Suite("GitHub release updates")
struct GitHubReleaseServiceTests {
    @Test("Uses the GitHub repository for release metadata and the appcast")
    func repositoryEndpoints() {
        #expect(AppLinks.releasesAPI.absoluteString == "https://api.github.com/repos/Lincb522/GitGatto/releases?per_page=100")
        #expect(AppLinks.updateFeed.absoluteString == "https://github.com/Lincb522/GitGatto/releases/latest/download/appcast.xml")
    }

    @Test("Follows GitHub's next release page")
    func decodesNextPageLink() {
        let header = #"<https://api.github.com/repositories/1/releases?per_page=100&page=2>; rel="next", <https://api.github.com/repositories/1/releases?per_page=100&page=4>; rel="last""#

        #expect(
            GitHubReleaseService.nextPageURL(from: header)?.absoluteString
                == "https://api.github.com/repositories/1/releases?per_page=100&page=2"
        )
        #expect(GitHubReleaseService.nextPageURL(from: nil) == nil)
    }

    @Test("Decodes published release notes and ignores drafts")
    func decodesReleaseNotes() throws {
        let data = Data(
            #"""
            [
              {
                "id": 14,
                "tag_name": "v0.14.0",
                "name": "GitGatto 0.14.0",
                "body": "## Added\n\n- GitHub release notes",
                "published_at": "2026-08-27T08:00:00Z",
                "html_url": "https://github.com/Lincb522/GitGatto/releases/tag/v0.14.0",
                "draft": false,
                "prerelease": false
              },
              {
                "id": 15,
                "tag_name": "v0.15.0-beta.1",
                "name": "",
                "body": null,
                "published_at": "2026-08-28T08:00:00Z",
                "html_url": "https://github.com/Lincb522/GitGatto/releases/tag/v0.15.0-beta.1",
                "draft": false,
                "prerelease": true
              },
              {
                "id": 16,
                "tag_name": "v0.16.0",
                "name": "Draft",
                "body": "Not published",
                "published_at": null,
                "html_url": "https://github.com/Lincb522/GitGatto/releases/tag/v0.16.0",
                "draft": true,
                "prerelease": false
              }
            ]
            """#.utf8
        )

        let releases = try GitHubReleaseService.decodeReleases(data)

        #expect(releases.map(\.version) == ["0.15.0-beta.1", "0.14.0"])
        #expect(releases[0].title == "v0.15.0-beta.1")
        #expect(releases[0].body.isEmpty)
        #expect(releases[0].isPrerelease)
        #expect(releases[1].title == "GitGatto 0.14.0")
        #expect(releases[1].body.contains("GitHub release notes"))
    }

    @Test("Keeps user-visible changes and removes development details")
    func filtersReleaseNotes() {
        let source = """
        ## 新增

        - 增加版本日志。

        ## 构建与打包

        - 调整 universal build pipeline。

        ## 修复

        - 修复检查更新状态。
        - 更新 DMG 打包脚本。
        """

        let filtered = ReleaseNotesContentFilter.userFacing(source)

        #expect(filtered.contains("增加版本日志"))
        #expect(filtered.contains("修复检查更新状态"))
        #expect(!filtered.contains("构建与打包"))
        #expect(!filtered.contains("build pipeline"))
        #expect(!filtered.contains("打包脚本"))
    }

    @Test("Bundles release notes in both supported languages")
    func bundledReleaseNotes() throws {
        for languages in [["en"], ["zh-Hans"]] {
            let url = try #require(L10n.localizedDocumentURL(
                named: "ReleaseNotes",
                preferredLanguages: languages
            ))
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
