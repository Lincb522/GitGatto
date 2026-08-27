import Testing
@testable import GitGatto

@Suite("Menu localization")
struct MenuLocalizationTests {
    @Test("Recognizes every standard top-level menu")
    func recognizesTopLevelMenus() {
        #expect(MenuTitleLocalizer.key(for: "File") == "menu.file")
        #expect(MenuTitleLocalizer.key(for: "Edit") == "menu.edit")
        #expect(MenuTitleLocalizer.key(for: "View") == "menu.view")
        #expect(MenuTitleLocalizer.key(for: "Repository") == "menu.repository")
        #expect(MenuTitleLocalizer.key(for: "Window") == "menu.window")
        #expect(MenuTitleLocalizer.key(for: "Help") == "menu.help")
    }

    @Test("Recognizes localized titles when the menu is refreshed")
    func recognizesChineseTitles() {
        #expect(MenuTitleLocalizer.key(for: "文件") == "menu.file")
        #expect(MenuTitleLocalizer.key(for: "编辑") == "menu.edit")
        #expect(MenuTitleLocalizer.key(for: "显示") == "menu.view")
        #expect(MenuTitleLocalizer.key(for: "仓库") == "menu.repository")
        #expect(MenuTitleLocalizer.key(for: "窗口") == "menu.window")
        #expect(MenuTitleLocalizer.key(for: "帮助") == "menu.help")
    }
}
