import Foundation
import Testing
@testable import GitGatto

@Suite("Product copy")
struct ProductCopyTests {
    @Test("Uses the official product slogan in both localizations")
    func usesOfficialProductSlogan() {
        let chinese = L10n.bundle(preferredLanguages: ["zh-Hans"])
        let english = L10n.bundle(preferredLanguages: ["en"])

        #expect(
            chinese.localizedString(forKey: "about.product", value: nil, table: nil)
                == "原生构建，由 Agent 驱动的 Git 管理工具。"
        )
        #expect(
            english.localizedString(forKey: "about.product", value: nil, table: nil)
                == "A native-built Git management tool, driven by Agent."
        )
    }

    @Test("Local commit confirmation states that the commit is not pushed")
    func marksLocalCommitAsUnpushed() {
        let chinese = L10n.bundle(preferredLanguages: ["zh-Hans"])
        let english = L10n.bundle(preferredLanguages: ["en"])

        #expect(
            chinese.localizedString(forKey: "notice.committed", value: nil, table: nil)
                == "提交已创建 · 尚未推送"
        )
        #expect(
            english.localizedString(forKey: "notice.committed", value: nil, table: nil)
                == "Commit created · Not pushed"
        )
    }

    @Test("Localizes goal and regression guides")
    func localizesGoalAndRegressionGuides() {
        let bundles = [
            L10n.bundle(preferredLanguages: ["zh-Hans"]),
            L10n.bundle(preferredLanguages: ["en"])
        ]
        let fixedKeys = [
            "help.topic.goals.title",
            "help.topic.goals.summary",
            "help.goals.create.title",
            "help.goals.execute.title",
            "help.goals.release.title",
            "help.topic.regression.title",
            "help.topic.regression.summary",
            "help.regression.start.title",
            "help.regression.verdict.title",
            "help.regression.fix.title",
            "goal.guide.title",
            "goal.guide.note",
            "regression.guide.title",
            "regression.guide.note",
            "workspace.guide.open",
            "workspace.guide.features",
            "workspace.guide.steps",
            "workspace.guide.open_full"
        ]
        let numberedKeys = [
            ("help.goals.create", 4),
            ("help.goals.execute", 4),
            ("help.goals.release", 3),
            ("help.regression.start", 4),
            ("help.regression.verdict", 3),
            ("help.regression.fix", 4),
            ("goal.guide.feature", 4),
            ("goal.guide.step", 4),
            ("regression.guide.feature", 4),
            ("regression.guide.step", 4)
        ].flatMap { entry in
            (1...entry.1).map { "\(entry.0).\($0)" }
        }

        for bundle in bundles {
            for key in fixedKeys + numberedKeys {
                let value = bundle.localizedString(forKey: key, value: key, table: nil)
                #expect(value != key)
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
