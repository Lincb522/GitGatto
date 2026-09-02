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
