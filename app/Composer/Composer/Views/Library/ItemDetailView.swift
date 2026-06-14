import SwiftUI

struct ItemDetailView: View {
    @ObservedObject var model: LibraryModel
    @EnvironmentObject private var app: AppState
    @State private var showDeleteConfirm = false
    @State private var pendingDelete: Item?

    var body: some View {
        switch model.detailState {
        case .empty:
            ContentUnavailableView(
                "Select an item",
                systemImage: "tray.full",
                description: Text("Pick an item from the library to see its contents.")
            )
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let msg):
            ContentUnavailableView(
                "Failed to load",
                systemImage: "exclamationmark.triangle",
                description: Text(msg)
            )
        case .loaded(let item):
            itemView(item)
                .confirmationDialog(
                    "Delete this item?",
                    isPresented: $showDeleteConfirm,
                    presenting: pendingDelete
                ) { item in
                    Button("Delete", role: .destructive) { model.delete(item) }
                    Button("Cancel", role: .cancel) {}
                } message: { item in
                    Text("\"\(item.title)\" will be permanently removed.")
                }
        }
    }

    @ViewBuilder
    private func itemView(_ item: Item) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(item)
                if let summary = item.summary, !summary.isEmpty {
                    section("Summary", sendableText: summary, item: item) {
                        RichContentView(content: summary, theme: app.theme, hasCurrentDraft: app.hasCurrentDraft) { kind, text in
                            app.quoteAs(kind: kind, selection: text, source: item.quoteSource)
                        }
                    }
                }
                if !item.keyPoints.isEmpty {
                    section(
                        "Key points",
                        sendableText: item.keyPoints.map { "- \($0)" }.joined(separator: "\n"),
                        item: item
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(item.keyPoints.enumerated()), id: \.offset) { _, kp in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•").foregroundStyle(.secondary)
                                    RichContentView(content: kp, theme: app.theme, hasCurrentDraft: app.hasCurrentDraft) { kind, text in
                                        app.quoteAs(kind: kind, selection: text, source: item.quoteSource)
                                    }
                                }
                            }
                        }
                    }
                }
                if !item.keywords.isEmpty {
                    HStack {
                        ForEach(item.keywords, id: \.self) { kw in
                            Text(kw)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
                if let content = item.content, !content.isEmpty {
                    section("Full text") {
                        RichContentView(content: content, theme: app.theme, hasCurrentDraft: app.hasCurrentDraft) { kind, text in
                            app.quoteAs(kind: kind, selection: text, source: item.quoteSource)
                        }
                    }
                }
                if !item.relatedLinks.isEmpty {
                    section("Related") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(item.relatedLinks, id: \.url) { link in
                                if let url = URL(string: link.url) {
                                    Link(link.title ?? link.url, destination: url)
                                        .font(.body)
                                } else {
                                    Text(link.title ?? link.url).font(.body)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(app.theme.backgroundColor)
        .foregroundStyle(app.theme.textColor, app.theme.secondaryTextColor)
        .tint(app.theme.accentColor)
        .font(app.typeface.font(size: 14))
    }

    @ViewBuilder
    private func header(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sourceLine(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(verboseSourceLine(item))
                Spacer(minLength: 8)
                if item.source == "datapoints" {
                    actionButton(
                        title: "Refresh",
                        runningTitle: "Refreshing…",
                        systemImage: "arrow.clockwise",
                        isRunning: model.isRefreshing,
                        help: "Re-fetch latest content from DataPoints"
                    ) {
                        model.refreshFromSource(item)
                    }
                }
                if let url = item.url, !url.isEmpty {
                    actionButton(
                        title: "Fetch full text",
                        runningTitle: "Fetching…",
                        systemImage: "doc.text.magnifyingglass",
                        isRunning: model.isFetchingContent,
                        help: "Fetch the original article and replace the full text"
                    ) {
                        model.fetchContent(item)
                    }
                }
                if let content = item.content, !content.isEmpty {
                    actionButton(
                        title: "Summarize",
                        runningTitle: "Summarizing…",
                        systemImage: "sparkles",
                        isRunning: model.isSummarizing,
                        help: "Generate a fresh summary and key points"
                    ) {
                        model.summarize(item)
                    }
                }
                Button(item.isArchived ? "Unarchive" : "Archive") {
                    model.toggleArchive(item)
                }
                .disabled(model.runningAction != nil)
                Button("Delete", role: .destructive) {
                    pendingDelete = item
                    showDeleteConfirm = true
                }
                .disabled(model.runningAction != nil)
            }
            Text(item.title)
                .font(.title2).bold()
            HStack(spacing: 6) {
                if let author = item.author, !author.isEmpty {
                    Text(author)
                }
                if item.author != nil, item.publishedAt != nil {
                    Text("·")
                }
                if let published = item.publishedAt {
                    Text(formatDateTime(published))
                }
                if let urlString = item.url, let url = URL(string: urlString) {
                    Text("·")
                    Link("original", destination: url)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let err = model.actionError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        runningTitle: String,
        systemImage: String,
        isRunning: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if isRunning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(runningTitle)
                }
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .disabled(model.runningAction != nil)
        .help(help)
    }

    /// Eyebrow line: `source · <compact ref>`. Since DataPoints items are now
    /// keyed by full URL, showing the raw `sourceRef` overflows the header, so
    /// prefer a short host (e.g. "venturebeat.com"). Legacy non-URL refs
    /// (numeric DataPoints ids, manual refs) are still shown verbatim.
    private func sourceLine(_ item: Item) -> String {
        var parts = [item.source]
        if let ref = compactSourceRef(item) { parts.append(ref) }
        var s = parts.joined(separator: " · ")
        if item.isArchived { s += " · archived" }
        return s
    }

    /// Full, untruncated source line for the hover tooltip.
    private func verboseSourceLine(_ item: Item) -> String {
        var s = item.source
        if let ref = item.sourceRef, !ref.isEmpty { s += " · \(ref)" }
        if item.isArchived { s += " · archived" }
        return s
    }

    private func compactSourceRef(_ item: Item) -> String? {
        if let host = host(from: item.url) ?? host(from: item.sourceRef) {
            return host
        }
        if let ref = item.sourceRef, !ref.isEmpty, !ref.contains("://") {
            return ref
        }
        return nil
    }

    /// Host of a URL string, minus a leading "www.". Returns nil for values
    /// that aren't URL-shaped (e.g. a bare numeric id).
    private func host(from string: String?) -> String? {
        guard let string, string.contains("://"),
              let host = URLComponents(string: string)?.host,
              !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        sendableText: String? = nil,
        item: Item? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if let sendableText, let item, !sendableText.isEmpty {
                    Button {
                        let kind: QuoteKind = app.hasCurrentDraft ? .appendToDraft : .draft
                        app.quoteAs(kind: kind, selection: sendableText, source: item.quoteSource)
                    } label: {
                        Label(
                            app.hasCurrentDraft ? "Append to Draft" : "New Draft",
                            systemImage: "arrow.right.doc.on.clipboard"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(app.hasCurrentDraft
                          ? "Append this section to the current draft"
                          : "Quote this section into a new draft")
                }
            }
            content()
        }
    }
}
