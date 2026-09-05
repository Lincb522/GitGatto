import AppKit
import Foundation
import SwiftUI

struct CodeDocumentView: View {
    let content: String
    let fileName: String
    var showsStatusBar = true
    var syntaxHighlighting = true

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }

    var body: some View {
        let palette = AppPalette(colorScheme)
        let lines = CodeLineCache.shared.lines(for: content)
        let gutterWidth = max(48, CGFloat(String(max(1, lines.count)).count * 8 + 24))

        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines.indices, id: \.self) { index in
                            CodeSurfaceLine(
                                number: index + 1,
                                text: lines[index],
                                fileName: fileName,
                                gutterWidth: gutterWidth,
                                highlightsSyntax: syntaxHighlighting,
                                theme: theme,
                                palette: palette
                            )
                        }
                    }
                    .frame(
                        minWidth: proxy.size.width,
                        minHeight: proxy.size.height,
                        alignment: .topLeading
                    )
                }
                .defaultScrollAnchor(.topLeading)
            }

            if showsStatusBar {
                Rectangle().fill(palette.divider).frame(height: 1)
                CodeSurfaceStatusBar(
                    fileName: fileName,
                    lineCount: lines.count,
                    theme: theme
                )
            }
        }
        .background(codeBackground(palette))
    }

    private func codeBackground(_ palette: AppPalette) -> Color {
        switch theme {
        case .standard: palette.background
        case .emerald, .folio, .lumen: palette.surface
        case .softGlass: palette.background.opacity(0.24)
        case .console: palette.background
        }
    }
}

final class CodeLineCache: @unchecked Sendable {
    static let shared = CodeLineCache()

    private final class Entry {
        let lines: [String]

        init(content: String) {
            lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }
    }

    private let storage = NSCache<NSString, Entry>()

    init() {
        storage.countLimit = 4
        storage.totalCostLimit = 8 * 1_024 * 1_024
    }

    func lines(for content: String) -> [String] {
        let key = content as NSString
        if let entry = storage.object(forKey: key) { return entry.lines }
        let entry = Entry(content: content)
        // Include the key and per-line storage, not just the source byte count.
        let cost = content.utf8.count * 2 + entry.lines.count * MemoryLayout<String>.stride
        if cost <= storage.totalCostLimit {
            storage.setObject(entry, forKey: key, cost: cost)
        }
        return entry.lines
    }
}

struct SyntaxHighlightedCodeLine: View {
    let text: String
    let fileName: String
    let palette: AppPalette
    var highlightsSyntax = true

    var body: some View {
        if highlightsSyntax {
            highlightedText(palette)
                .textSelection(.enabled)
        } else {
            Text(text.isEmpty ? " " : text)
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
        }
    }

    private func highlightedText(_ palette: AppPalette) -> Text {
        CodeSyntax.tokenize(text, fileName: fileName).reduce(Text("")) { result, token in
            let fragment = Text(token.value)
                .foregroundColor(token.kind.color(palette))
                .fontWeight(token.kind.fontWeight)
            return result + (token.kind == .comment ? fragment.italic() : fragment)
        }
    }
}

private struct CodeSurfaceLine: View {
    let number: Int
    let text: String
    let fileName: String
    let gutterWidth: CGFloat
    let highlightsSyntax: Bool
    let theme: AppVisualTheme
    let palette: AppPalette

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 7) {
                if hovering {
                    Circle()
                        .fill(palette.primary)
                        .frame(width: 4, height: 4)
                }
                Text("\(number)")
                    .foregroundStyle(hovering ? palette.mutedInk : palette.subtleInk)
            }
            .frame(width: gutterWidth - 11, alignment: .trailing)
            .padding(.trailing, 11)
            .frame(maxHeight: .infinity)
            .background(gutterBackground(palette))

            Rectangle()
                .fill(hovering ? palette.primary.opacity(0.34) : palette.divider)
                .frame(width: 1)

            SyntaxHighlightedCodeLine(
                text: text,
                fileName: fileName,
                palette: palette,
                highlightsSyntax: highlightsSyntax
            )
            .padding(.leading, 14)
            .padding(.trailing, 22)
        }
        .font(.system(size: theme == .console ? 11 : 11.5, weight: .regular, design: .monospaced))
        .frame(height: theme == .console ? 21 : 22)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? palette.primarySoft.opacity(0.42) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func gutterBackground(_ palette: AppPalette) -> Color {
        switch theme {
        case .standard: palette.sidebar.opacity(0.60)
        case .emerald, .folio, .lumen: palette.background.opacity(0.72)
        case .softGlass: palette.sidebar.opacity(0.22)
        case .console: palette.sidebar.opacity(0.72)
        }
    }
}

private struct CodeSurfaceStatusBar: View {
    let fileName: String
    let lineCount: Int
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 12) {
            GattoLabel(CodeSyntax.languageName(for: fileName), systemImage: "curlybraces.square")
            Spacer()
            Text("UTF-8")
            Text("LF")
            Text(L10n.format("code_surface.lines", lineCount))
        }
        .font(.system(size: 9.5, weight: .medium, design: theme == .console ? .monospaced : .default))
        .foregroundStyle(palette.subtleInk)
        .padding(.horizontal, 12)
        .frame(height: 29)
        .background(theme == .softGlass ? palette.surface.opacity(0.16) : palette.surface)
    }
}

fileprivate struct CodeToken {
    let value: String
    let kind: CodeTokenKind
}

fileprivate enum CodeTokenKind {
    case plain
    case keyword
    case type
    case string
    case number
    case comment
    case directive

    var fontWeight: Font.Weight {
        switch self {
        case .keyword, .directive: .semibold
        case .type: .medium
        default: .regular
        }
    }

    func color(_ palette: AppPalette) -> Color {
        switch self {
        case .plain: palette.ink
        case .keyword: palette.primary
        case .type: palette.accent
        case .string: palette.success
        case .number: palette.warning
        case .comment: palette.subtleInk
        case .directive: palette.danger
        }
    }
}

enum CodeSyntax {
    private static let tokenCache = CodeTokenCache()
    private static let keywords: Set<String> = [
        "actor", "async", "await", "break", "case", "catch", "class", "const", "continue",
        "default", "defer", "do", "else", "enum", "export", "extends", "false", "final",
        "for", "from", "func", "function", "guard", "if", "import", "in", "init", "interface",
        "internal", "is", "let", "mutating", "nil", "none", "null", "open", "override", "private",
        "protocol", "public", "return", "self", "some", "static", "struct", "switch", "throws",
        "true", "try", "typealias", "var", "where", "while", "with", "yield"
    ]

    fileprivate static func tokenize(_ line: String, fileName: String) -> [CodeToken] {
        guard !line.isEmpty else { return [CodeToken(value: " ", kind: .plain)] }
        let extensionName = (fileName as NSString).pathExtension.lowercased()
        let cacheKey = "\(extensionName)\u{0}\(line)" as NSString
        if let cached = tokenCache.value(for: cacheKey) {
            return cached
        }
        let hashComments = ["py", "rb", "sh", "bash", "zsh", "yml", "yaml", "toml"].contains(extensionName)
        var tokens: [CodeToken] = []
        var index = line.startIndex

        func matches(_ value: String, at position: String.Index) -> Bool {
            line[position...].hasPrefix(value)
        }

        while index < line.endIndex {
            if matches("//", at: index) || (hashComments && matches("#", at: index)) {
                tokens.append(CodeToken(value: String(line[index...]), kind: .comment))
                break
            }

            let character = line[index]
            if character == "\"" || character == "'" || character == "`" {
                let quote = character
                var end = line.index(after: index)
                var escaped = false
                while end < line.endIndex {
                    let value = line[end]
                    if value == quote, !escaped {
                        end = line.index(after: end)
                        break
                    }
                    escaped = value == "\\" && !escaped
                    if value != "\\" { escaped = false }
                    end = line.index(after: end)
                }
                tokens.append(CodeToken(value: String(line[index..<end]), kind: .string))
                index = end
                continue
            }

            if character.isNumber {
                var end = line.index(after: index)
                while end < line.endIndex, line[end].isNumber || ".xabcdefABCDEF_".contains(line[end]) {
                    end = line.index(after: end)
                }
                tokens.append(CodeToken(value: String(line[index..<end]), kind: .number))
                index = end
                continue
            }

            if character.isLetter || character == "_" || character == "$" {
                var end = line.index(after: index)
                while end < line.endIndex,
                      line[end].isLetter || line[end].isNumber || line[end] == "_" || line[end] == "$" {
                    end = line.index(after: end)
                }
                let word = String(line[index..<end])
                let kind: CodeTokenKind
                if keywords.contains(word.lowercased()) {
                    kind = .keyword
                } else if word.first?.isUppercase == true {
                    kind = .type
                } else {
                    kind = .plain
                }
                tokens.append(CodeToken(value: word, kind: kind))
                index = end
                continue
            }

            if character == "#", !hashComments {
                var end = line.index(after: index)
                while end < line.endIndex, line[end].isLetter {
                    end = line.index(after: end)
                }
                tokens.append(CodeToken(value: String(line[index..<end]), kind: .directive))
                index = end
                continue
            }

            var end = line.index(after: index)
            while end < line.endIndex {
                let value = line[end]
                if value.isLetter || value.isNumber || value == "_" || value == "$"
                    || value == "\"" || value == "'" || value == "`"
                    || matches("//", at: end) || (hashComments && matches("#", at: end)) {
                    break
                }
                end = line.index(after: end)
            }
            tokens.append(CodeToken(value: String(line[index..<end]), kind: .plain))
            index = end
        }
        tokenCache.insert(tokens, for: cacheKey)
        return tokens
    }

    static func languageName(for fileName: String) -> String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "swift": "Swift"
        case "m", "mm": "Objective-C"
        case "c", "h": "C"
        case "cpp", "cc", "hpp": "C++"
        case "js", "jsx": "JavaScript"
        case "ts", "tsx": "TypeScript"
        case "py": "Python"
        case "rs": "Rust"
        case "go": "Go"
        case "rb": "Ruby"
        case "sh", "bash", "zsh": "Shell"
        case "yml", "yaml": "YAML"
        case "json": "JSON"
        case "md", "markdown": "Markdown"
        case "html": "HTML"
        case "css", "scss", "sass": "CSS"
        case "xml": "XML"
        default: L10n.text("code_surface.plain_text")
        }
    }
}

private final class CodeTokenBox {
    let tokens: [CodeToken]

    init(_ tokens: [CodeToken]) {
        self.tokens = tokens
    }
}

private final class CodeTokenCache: @unchecked Sendable {
    private let storage: NSCache<NSString, CodeTokenBox>

    init() {
        storage = NSCache<NSString, CodeTokenBox>()
        storage.countLimit = 2_048
    }

    func value(for key: NSString) -> [CodeToken]? {
        storage.object(forKey: key)?.tokens
    }

    func insert(_ tokens: [CodeToken], for key: NSString) {
        storage.setObject(CodeTokenBox(tokens), forKey: key)
    }
}

struct CodeTextEditorView: NSViewRepresentable {
    @Binding var text: String
    let fileName: String
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 14, height: 10)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        scrollView.documentView = textView

        let ruler = CodeLineNumberRuler(scrollView: scrollView, textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.configure(
            colorScheme: context.environment.colorScheme,
            themeRaw: themeRaw
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let textView = context.coordinator.textView, textView.string != text {
            textView.string = text
        }
        context.coordinator.configure(
            colorScheme: context.environment.colorScheme,
            themeRaw: themeRaw
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextEditorView
        weak var textView: NSTextView?
        weak var ruler: CodeLineNumberRuler?
        private var isApplyingAttributes = false
        private var currentPalette: AppPalette?
        private var currentTheme = AppStyleDefaults.defaultTheme
        private var currentLineColor = NSColor.clear

        init(_ parent: CodeTextEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingAttributes, let textView else { return }
            parent.text = textView.string
            applyAttributes()
            updateCurrentLineHighlight()
            ruler?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            updateCurrentLineHighlight()
            ruler?.needsDisplay = true
        }

        func configure(colorScheme: ColorScheme, themeRaw: String) {
            guard let textView else { return }
            let theme = AppVisualTheme.resolved(themeRaw)
            let palette = AppPalette(colorScheme, theme: theme)
            currentTheme = theme
            currentPalette = palette
            currentLineColor = NSColor(palette.primarySoft).withAlphaComponent(0.38)
            let background = NSColor(palette.background)
            textView.backgroundColor = background
            textView.insertionPointColor = NSColor(palette.primary)
            textView.selectedTextAttributes = [
                .backgroundColor: NSColor(palette.primarySoft),
                .foregroundColor: NSColor(palette.ink)
            ]
            textView.enclosingScrollView?.backgroundColor = background
            ruler?.configure(
                background: NSColor(palette.sidebar),
                divider: NSColor(palette.divider),
                text: NSColor(palette.subtleInk),
                activeText: NSColor(palette.primary)
            )
            applyAttributes(palette: palette, theme: theme)
            updateCurrentLineHighlight()
        }

        private func applyAttributes(
            palette: AppPalette? = nil,
            theme: AppVisualTheme? = nil
        ) {
            guard let textView, let storage = textView.textStorage else { return }
            let resolvedTheme = theme ?? currentTheme
            let resolvedPalette = palette ?? currentPalette ?? AppPalette(.light, theme: resolvedTheme)
            let range = NSRange(location: 0, length: storage.length)
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = resolvedTheme == .console ? 19 : 20
            paragraph.maximumLineHeight = resolvedTheme == .console ? 19 : 20
            isApplyingAttributes = true
            storage.beginEditing()
            storage.setAttributes([
                .font: NSFont.monospacedSystemFont(
                    ofSize: resolvedTheme == .console ? 10.5 : 11.5,
                    weight: .regular
                ),
                .foregroundColor: NSColor(resolvedPalette.ink),
                .paragraphStyle: paragraph
            ], range: range)
            highlight("(?m)//.*$", color: NSColor(resolvedPalette.subtleInk), in: storage)
            highlight(
                "(?m)^(<<<<<<<.*|=======|>>>>>>>.*)$",
                color: NSColor(resolvedPalette.danger),
                background: NSColor(resolvedPalette.dangerSoft),
                in: storage,
                weight: .semibold
            )
            highlight("\\b(actor|async|await|class|enum|extension|func|guard|if|import|init|let|private|protocol|public|return|some|static|struct|switch|throws|true|false|try|var|while)\\b", color: NSColor(resolvedPalette.primary), in: storage, weight: .semibold)
            highlight("\\b[A-Z][A-Za-z0-9_]*\\b", color: NSColor(resolvedPalette.accent), in: storage)
            highlight("\"(?:\\\\.|[^\"\\\\])*\"", color: NSColor(resolvedPalette.success), in: storage)
            storage.endEditing()
            isApplyingAttributes = false
            ruler?.needsDisplay = true
        }

        private func highlight(
            _ pattern: String,
            color: NSColor,
            background: NSColor? = nil,
            in storage: NSTextStorage,
            weight: NSFont.Weight = .regular
        ) {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
            let range = NSRange(location: 0, length: storage.length)
            for match in expression.matches(in: storage.string, range: range) {
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
                if let background {
                    storage.addAttribute(.backgroundColor, value: background, range: match.range)
                }
                if weight != .regular {
                    storage.addAttribute(
                        .font,
                        value: NSFont.monospacedSystemFont(
                            ofSize: AppVisualTheme.resolved(parent.themeRaw) == .console ? 10.5 : 11.5,
                            weight: weight
                        ),
                        range: match.range
                    )
                }
            }
        }

        private func updateCurrentLineHighlight() {
            guard let textView, let layoutManager = textView.layoutManager else { return }
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
            let lineRange = (textView.string as NSString).lineRange(for: textView.selectedRange())
            guard lineRange.length > 0 else { return }
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: currentLineColor,
                forCharacterRange: lineRange
            )
        }
    }
}

@MainActor
final class CodeLineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?
    private var backgroundColor = NSColor.windowBackgroundColor
    private var dividerColor = NSColor.separatorColor
    private var textColor = NSColor.secondaryLabelColor
    private var activeTextColor = NSColor.controlAccentColor

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 48
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError()
    }

    override var isFlipped: Bool { true }

    func configure(background: NSColor, divider: NSColor, text: NSColor, activeText: NSColor) {
        backgroundColor = background
        dividerColor = divider
        textColor = text
        activeTextColor = activeText
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        backgroundColor.setFill()
        bounds.fill()
        dividerColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        let string = textView.string as NSString
        if string.length == 0 {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            NSString(string: "1").draw(
                in: NSRect(x: 0, y: textView.textContainerInset.height + 1, width: ruleThickness - 10, height: 16),
                withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: activeTextColor,
                    .paragraphStyle: paragraph
                ]
            )
            return
        }
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: textView.visibleRect,
            in: textContainer
        )
        let visibleCharacterRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange,
            actualGlyphRange: nil
        )
        let selectedLineRange = string.lineRange(for: textView.selectedRange())
        var lineNumber = 1
        if visibleCharacterRange.location > 0 {
            lineNumber += string.substring(to: visibleCharacterRange.location)
                .reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
        }
        var characterIndex = string.lineRange(
            for: NSRange(location: min(visibleCharacterRange.location, string.length), length: 0)
        ).location

        repeat {
            let lineRange = string.lineRange(
                for: NSRange(location: min(characterIndex, string.length), length: 0)
            )
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(characterIndex, max(0, string.length - 1)))
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let y = lineRect.minY + textView.textContainerInset.height - textView.visibleRect.minY
            let active = NSLocationInRange(characterIndex, selectedLineRange)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: active ? .semibold : .regular),
                .foregroundColor: active ? activeTextColor : textColor,
                .paragraphStyle: paragraph
            ]
            NSString(string: "\(lineNumber)").draw(
                in: NSRect(x: 0, y: y + 1, width: ruleThickness - 10, height: lineRect.height),
                withAttributes: attributes
            )
            let next = NSMaxRange(lineRange)
            if next <= characterIndex || next > NSMaxRange(visibleCharacterRange) { break }
            characterIndex = next
            lineNumber += 1
        } while characterIndex <= string.length
    }
}
