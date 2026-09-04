import SwiftUI

struct GitCommitSearchSheet: View {
    @ObservedObject var searchModel: GitCommitSearchViewModel
    let repositoryURL: URL?
    let selectCommit: (CommitRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var includesSince = false
    @State private var includesUntil = false
    @State private var since = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var until = Date()

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(gattoSymbol: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .frame(width: 38, height: 38)
                    .background(palette.primarySoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("commit_search.title"))
                        .font(.system(size: 17, weight: .semibold))
                    Text(repositoryURL?.lastPathComponent ?? L10n.text("repository.none"))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                }
                Spacer()
                Button(L10n.text("action.reset")) {
                    searchModel.reset()
                    includesSince = false
                    includesUntil = false
                }
                .buttonStyle(.borderless)
                Button(L10n.text("action.close")) { dismiss() }
                    .buttonStyle(.borderless)
                Button {
                    runSearch()
                } label: {
                    HStack(spacing: 6) {
                        if searchModel.isSearching { ProgressView().controlSize(.small) }
                        else { Image(gattoSymbol: "magnifyingglass") }
                        Text(L10n.text("commit_search.action"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(repositoryURL == nil || searchModel.isSearching)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(18)
            Rectangle().fill(palette.divider).frame(height: 1)

            GeometryReader { proxy in
                HStack(spacing: 0) {
                    criteria(palette)
                        .frame(width: min(430, max(330, proxy.size.width * 0.43)))
                    Rectangle().fill(palette.divider).frame(width: 1)
                    results(palette)
                }
            }
        }
        .background(palette.surface)
        .onAppear {
            if let date = searchModel.query.since { includesSince = true; since = date }
            if let date = searchModel.query.until { includesUntil = true; until = date }
        }
    }

    private func criteria(_ palette: AppPalette) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                criteriaField("commit_search.hash", text: binding(\.hash), symbol: "number")
                criteriaField("commit_search.message", text: binding(\.message), symbol: "text.quote")
                criteriaField("commit_search.author", text: binding(\.author), symbol: "person")
                criteriaField("commit_search.revision", text: binding(\.revision), symbol: "arrow.triangle.branch")
                criteriaField("commit_search.path", text: binding(\.path), symbol: "folder")
                criteriaField("commit_search.changed_text", text: binding(\.changedText), symbol: "text.magnifyingglass")
                criteriaField("commit_search.extension", text: binding(\.fileExtension), symbol: "doc")

                VStack(alignment: .leading, spacing: 9) {
                    Toggle(L10n.text("commit_search.since"), isOn: $includesSince)
                    if includesSince {
                        DatePicker("", selection: $since, displayedComponents: .date)
                            .labelsHidden()
                    }
                    Toggle(L10n.text("commit_search.until"), isOn: $includesUntil)
                    if includesUntil {
                        DatePicker("", selection: $until, displayedComponents: .date)
                            .labelsHidden()
                    }
                    Toggle(L10n.text("commit_search.merges"), isOn: binding(\.mergesOnly))
                }
                .font(.system(size: 11.5, weight: .medium))
                .padding(12)
                .background(palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(palette.divider) }

                Text(L10n.text("commit_search.hint"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.subtleInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(palette.sidebar)
    }

    private func criteriaField(
        _ key: String,
        text: Binding<String>,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(L10n.text(key), systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { runSearch() }
        }
    }

    @ViewBuilder
    private func results(_ palette: AppPalette) -> some View {
        if searchModel.isSearching, searchModel.results.isEmpty {
            GattoLoadingState(text: L10n.text("commit_search.loading"))
        } else if let error = searchModel.errorMessage {
            VStack(spacing: 12) {
                Image(gattoSymbol: "exclamationmark.triangle")
                    .font(.system(size: 22))
                    .foregroundStyle(palette.danger)
                Text(error)
                    .font(.system(size: 11.5))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                Button(L10n.text("action.retry"), action: runSearch)
                    .buttonStyle(.borderedProminent)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchModel.hasSearched, searchModel.results.isEmpty {
            InspectorEmptyState(
                image: "magnifyingglass",
                titleKey: "commit_search.empty.title",
                bodyKey: "commit_search.empty.body"
            )
        } else if !searchModel.hasSearched {
            InspectorEmptyState(
                image: "clock.arrow.circlepath",
                titleKey: "commit_search.start.title",
                bodyKey: "commit_search.start.body"
            )
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text(L10n.format("commit_search.results", searchModel.results.count))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.mutedInk)
                    Spacer()
                    if searchModel.isSearching { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                Rectangle().fill(palette.divider).frame(height: 1)
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(searchModel.results) { commit in
                            Button {
                                selectCommit(commit)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(commit.shortHash)
                                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(palette.primary)
                                        .frame(width: 70, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(commit.subject)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(palette.ink)
                                            .lineLimit(2)
                                        HStack(spacing: 7) {
                                            Text(commit.author).lineLimit(1)
                                            Text(commit.date.formatted(date: .abbreviated, time: .shortened))
                                        }
                                        .font(.system(size: 10))
                                        .foregroundStyle(palette.subtleInk)
                                    }
                                    Spacer()
                                    Image(gattoSymbol: "arrow.right")
                                        .foregroundStyle(palette.subtleInk)
                                }
                                .padding(11)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(palette.raisedSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 10).stroke(palette.divider) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CommitSearchQuery, Value>) -> Binding<Value> {
        Binding(
            get: { searchModel.query[keyPath: keyPath] },
            set: { searchModel.query[keyPath: keyPath] = $0 }
        )
    }

    private func runSearch() {
        searchModel.query.since = includesSince ? Calendar.current.startOfDay(for: since) : nil
        if includesUntil {
            searchModel.query.until = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: until))
        } else {
            searchModel.query.until = nil
        }
        searchModel.search(in: repositoryURL)
    }
}
