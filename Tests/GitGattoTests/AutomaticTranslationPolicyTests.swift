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

    @Test("Sentence punctuation around bare URLs is translatable")
    func translatedURLPunctuation() {
        for (source, translation) in [
            ("Visit https://example.invalid/docs for details.", "详情请访问 https://example.invalid/docs。"),
            ("Read https://example.invalid/docs.", "阅读 https://example.invalid/docs。"),
            ("See https://example.invalid/docs, then restart.", "请参阅 https://example.invalid/docs，然后重启。"),
            ("Open https://example.invalid/docs?lang=en#setup!", "打开 https://example.invalid/docs?lang=en#setup！"),
        ] {
            #expect(TranslationContentGuard.preservesProtectedContent(source: source, translation: translation))
        }
    }

    @Test("URL destinations remain protected after punctuation normalization")
    func retainsURLIntegrity() {
        let source = "Visit https://example.invalid/docs?lang=en#setup."
        for translation in [
            "访问 https://other.invalid/docs?lang=en#setup。",
            "访问 https://example.invalid/other?lang=en#setup。",
            "访问 https://example.invalid/docs?lang=zh#setup。",
            "访问 https://example.invalid/docs?lang=en#other。",
            "访问 https://example.invalid/docs?lang=en#setup。 https://example.invalid/extra",
        ] {
            #expect(!TranslationContentGuard.preservesProtectedContent(source: source, translation: translation))
        }
        #expect(!TranslationContentGuard.preservesProtectedContent(
            source: "[Guide](https://example.invalid/docs.)",
            translation: "[指南](https://example.invalid/docs)"
        ))
        #expect(!TranslationContentGuard.preservesProtectedContent(
            source: "<a href=\"https://example.invalid/docs.\">Guide</a>",
            translation: "<a href=\"https://example.invalid/docs\">指南</a>"
        ))
    }

    @Test("Equivalent HTML entity encodings preserve text content")
    func equivalentHTMLEntities() {
        #expect(TranslationContentGuard.preservesProtectedContent(
            source: "Alice&#39;s guide &amp; examples &quot;quoted&quot;",
            translation: "Alice&apos;s 指南 &#38; 示例 &#x22;引用&#X22;"
        ))
        #expect(!TranslationContentGuard.preservesProtectedContent(
            source: "Commands &amp; examples", translation: "命令 &lt; 示例"
        ))
        #expect(!TranslationContentGuard.preservesProtectedContent(
            source: "Commands &amp; examples", translation: "命令和示例"
        ))
        #expect(!TranslationContentGuard.preservesProtectedContent(
            source: "Use `echo &amp;`", translation: "使用 `echo &#38;`"
        ))
    }

}
