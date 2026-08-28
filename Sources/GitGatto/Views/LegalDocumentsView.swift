import AppKit
import SwiftUI

struct LegalDocumentsView: View {
    @ObservedObject var navigation: AppNavigationModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var documentText = ""

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: AppThemeLayout.panelSpacing) {
            VStack(spacing: 0) {
                AppBrandLockup(iconSize: 34, wordmarkWidth: 88, spacing: 7)
                    .padding(
                        .leading,
                        AppThemeLayout.titlebarBrandLeading - AppThemeLayout.workspaceInset
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 66)

                Rectangle().fill(palette.divider).frame(height: 1)

                VStack(spacing: 5) {
                    ForEach(LegalDocumentKind.allCases) { document in
                        Button {
                            navigation.selectedLegalDocument = document
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: document.icon)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .frame(width: 18)
                                Text(L10n.text(document.titleKey))
                                    .font(.system(size: 12, weight: navigation.selectedLegalDocument == document ? .semibold : .medium))
                                Spacer()
                            }
                            .foregroundStyle(navigation.selectedLegalDocument == document ? palette.ink : palette.mutedInk)
                            .padding(.horizontal, 11)
                            .frame(height: 40)
                            .background(navigation.selectedLegalDocument == document ? palette.primarySoft : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                Spacer()
            }
            .frame(width: 210)
            .background(palette.sidebar.opacity(0.18))
            .appGlassPanel()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.text(navigation.selectedLegalDocument.titleKey))
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(palette.ink)
                        Text(L10n.text(navigation.selectedLegalDocument.summaryKey))
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.mutedInk)
                    }
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(documentText, forType: .string)
                    } label: {
                        Label(L10n.text("legal.copy"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)

                Rectangle().fill(palette.divider).frame(height: 1)

                ScrollView {
                    LegalMarkdownDocument(text: documentText)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(navigation.selectedLegalDocument)
            }
            .background(palette.surface.opacity(0.18))
            .appGlassPanel()
        }
        .padding(AppThemeLayout.workspaceInset)
        .frame(minWidth: 840, minHeight: 620)
        .background(Color.clear)
        .ignoresSafeArea(.container, edges: .top)
        .task(id: navigation.selectedLegalDocument) {
            documentText = loadDocument(navigation.selectedLegalDocument)
        }
#if DEBUG
        .background(
            DebugSnapshotCapture(
                isReady: ProcessInfo.processInfo.environment["GITGATTO_LEGAL_PREVIEW"] == "1"
                    && !documentText.isEmpty
            )
        )
#endif
    }

    private func loadDocument(_ document: LegalDocumentKind) -> String {
        guard let url = L10n.legalDocumentURL(named: document.fileName),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return L10n.text("legal.load_failed")
        }
        return text
    }
}

private struct LegalMarkdownDocument: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    private var blocks: [LegalMarkdownBlock] {
        LegalMarkdownBlock.parse(text)
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                switch block.kind {
                case .title:
                    Text(block.text)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(palette.ink)
                        .padding(.bottom, 6)
                case .heading:
                    Text(block.text)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.ink)
                        .padding(.top, 8)
                case .paragraph:
                    Text((try? AttributedString(markdown: block.text)) ?? AttributedString(block.text))
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.mutedInk)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct LegalMarkdownBlock: Identifiable {
    enum Kind { case title, heading, paragraph }

    let id: Int
    let kind: Kind
    let text: String

    static func parse(_ source: String) -> [LegalMarkdownBlock] {
        var result: [LegalMarkdownBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(.init(id: result.count, kind: .paragraph, text: paragraph.joined(separator: " ")))
            paragraph.removeAll(keepingCapacity: true)
        }

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("# ") {
                flushParagraph()
                result.append(.init(id: result.count, kind: .title, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("## ") {
                flushParagraph()
                result.append(.init(id: result.count, kind: .heading, text: String(line.dropFirst(3))))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return result
    }
}
