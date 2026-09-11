import Foundation
import Testing
@testable import GitGatto

@Suite("Automatic translation language detection")
struct AutomaticTranslationPolicyTests {
    @Test("Translates English prose to the configured Chinese target")
    func translatesEnglishToChinese() {
        let target = AutomaticTranslationPolicy.target(
            forHTML: "<h1>Repository</h1><p>Review changes, browse history, and manage releases from the project workspace.</p>",
            preferredTarget: .simplifiedChinese
        )

        #expect(target == .simplifiedChinese)
    }

    @Test("Keeps content already written in the target language")
    func keepsMatchingLanguage() {
        let target = AutomaticTranslationPolicy.target(
            forHTML: "<h1>仓库</h1><p>查看代码改动、提交历史、发行版本以及项目协作状态。</p>",
            preferredTarget: .simplifiedChinese
        )

        #expect(target == nil)
    }

    @Test("Uses the configured English target for Chinese source content")
    func translatesChineseToEnglish() {
        let target = AutomaticTranslationPolicy.target(
            for: "查看代码改动、提交历史、发行版本以及项目协作状态。所有结果都在当前项目中显示。",
            preferredTarget: .english
        )

        #expect(target == .english)
    }

    @Test("Translates source prose across language families")
    func translatesEveryDetectedSourceLanguage() {
        let samples = [
            "Gérez les dépôts, consultez l’historique et téléchargez les versions publiées depuis cet espace de travail.",
            "リポジトリの変更、コミット履歴、公開されたリリースを一つの画面で確認できます。",
            "저장소 변경 사항과 커밋 기록, 배포된 릴리스를 하나의 작업 공간에서 확인할 수 있습니다.",
            "Просматривайте изменения репозитория, историю коммитов и опубликованные выпуски в одном рабочем пространстве.",
            "يمكنك مراجعة تغييرات المستودع وسجل الالتزامات والإصدارات المنشورة من مساحة عمل واحدة.",
            "Administra repositorios, revisa el historial y descarga versiones publicadas desde el mismo espacio de trabajo."
        ]

        for sample in samples {
            #expect(AutomaticTranslationPolicy.target(
                for: sample,
                preferredTarget: .simplifiedChinese
            ) == .simplifiedChinese)
        }
    }

    @Test("Does not translate an icon-only or code-only document")
    func skipsDocumentsWithoutProse() {
        let target = AutomaticTranslationPolicy.target(
            forHTML: "<svg></svg><pre><code>let value = repository.status</code></pre>",
            preferredTarget: .simplifiedChinese
        )

        #expect(target == nil)
    }
}

extension AutomaticTranslationPolicyTests {
    @Test func shortAndMixedProse() {
        #expect(AutomaticTranslationPolicy.target(for: "Try again", preferredTarget: .simplifiedChinese) == .simplifiedChinese)
        #expect(AutomaticTranslationPolicy.target(for: "保存失败", preferredTarget: .english) == .english)
        #expect(AutomaticTranslationPolicy.target(for: "这里是项目的中文介绍和详细说明。\nPlease restart the application.", preferredTarget: .simplifiedChinese) == .simplifiedChinese)
        #expect(AutomaticTranslationPolicy.target(for: "Git", preferredTarget: .simplifiedChinese) == nil)
        #expect(AutomaticTranslationPolicy.target(for: "`npm install package` https://example.com/readme", preferredTarget: .simplifiedChinese) == nil)
    }
    @Test func translationPreservesCodeTermsLinksAndNumbers() {
        let source = "Install Node.js 22 from [GitHub](https://example.invalid/repo). Use `npm install` and src/main.swift.\n```swift\nlet value = 42\n```\n"
        let translated = "从 [GitHub](https://example.invalid/repo) 安装 Node.js 22。使用 `npm install` 和 src/main.swift。\n```swift\nlet value = 42\n```\n"
        #expect(TranslationContentGuard.preservesProtectedContent(source: source, translation: translated))
        for (before, after) in [("npm install", "npm update"), ("22", "23"), ("GitHub", "代码站"), ("example.invalid", "changed.invalid"), ("value = 42", "value = 43")] {
            #expect(!TranslationContentGuard.preservesProtectedContent(source: source, translation: translated.replacingOccurrences(of: before, with: after)))
        }
        #expect(!TranslationContentGuard.preservesProtectedContent(source: "Try again", translation: "<script>alert(1)</script>再试"))
        #expect(TranslationContentGuard.preservesProtectedContent(source: "Install Git", translation: "安装Git"))
        #expect(TranslationContentGuard.preservesProtectedContent(source: "Réessayez", translation: "重试"))
    }

}
