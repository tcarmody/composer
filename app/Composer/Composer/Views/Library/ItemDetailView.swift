import SwiftUI

struct ItemDetailView: View {
    @ObservedObject var model: LibraryModel
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
                    section("Summary") {
                        Text(summary).font(.body)
                    }
                }
                if !item.keyPoints.isEmpty {
                    section("Key points") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(item.keyPoints.enumerated()), id: \.offset) { _, kp in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(kp)
                                }
                            }
                        }
                        .font(.body)
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
                        Text(content)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    @ViewBuilder
    private func header(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sourceLine(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button(item.isArchived ? "Unarchive" : "Archive") {
                    model.toggleArchive(item)
                }
                Button("Delete", role: .destructive) {
                    pendingDelete = item
                    showDeleteConfirm = true
                }
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
        }
    }

    private func sourceLine(_ item: Item) -> String {
        var s = item.source
        if let ref = item.sourceRef { s += " · \(ref)" }
        if item.isArchived { s += " · archived" }
        return s
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption).bold()
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}
