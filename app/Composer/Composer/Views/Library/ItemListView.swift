import AppKit
import SwiftUI

struct ItemListView: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.composerDensity) private var density
    @State private var pendingDelete: ItemSummary?
    @State private var showDeleteConfirm = false

    var body: some View {
        content
            .confirmationDialog(
                "Delete this item?",
                isPresented: $showDeleteConfirm,
                presenting: pendingDelete
            ) { item in
                Button("Delete", role: .destructive) { model.delete(id: item.id) }
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text("\"\(item.title)\" will be permanently removed.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.listState {
        case .idle, .loading:
            DelayedProgressView()
        case .error(let msg):
            Text("Failed to load: \(msg)")
                .font(.caption)
                .foregroundStyle(.red)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .loaded(let response):
            if response.items.isEmpty {
                ContentUnavailableView(
                    model.query.isEmpty ? "No items" : "No matches",
                    systemImage: "tray",
                    description: Text(emptyMessage)
                )
            } else {
                List(selection: Binding(
                    get: { model.selectedId },
                    set: { model.select($0) }
                )) {
                    Section {
                        ForEach(response.items) { item in
                            ItemRowView(item: item, density: density)
                                .tag(item.id)
                                .contextMenu { rowMenu(for: item) }
                        }
                    } header: {
                        Text("\(response.total) item\(response.total == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
                .composerSurface(.list)
                .reloadIndicator(model.isListReloading)
            }
        }
    }

    @ViewBuilder
    private func rowMenu(for item: ItemSummary) -> some View {
        let busy = model.runningAction != nil
        Button {
            model.refreshFromSource(id: item.id)
        } label: {
            Label("Refresh from source", systemImage: "arrow.clockwise")
        }
        .disabled(busy)

        Button {
            model.fetchContent(id: item.id)
        } label: {
            Label("Fetch full content", systemImage: "doc.text.magnifyingglass")
        }
        .disabled(busy)

        Button {
            model.summarize(id: item.id)
        } label: {
            Label("Summarize", systemImage: "sparkles")
        }
        .disabled(busy)

        Divider()

        Button {
            model.toggleArchive(id: item.id, isArchived: item.isArchived)
        } label: {
            Label(
                item.isArchived ? "Unarchive" : "Archive",
                systemImage: item.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }

        if let url = item.url, !url.isEmpty, let parsed = URL(string: url) {
            Button {
                NSWorkspace.shared.open(parsed)
            } label: {
                Label("Open in browser", systemImage: "safari")
            }
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(url, forType: .string)
            } label: {
                Label("Copy link", systemImage: "link")
            }
        }

        Divider()

        Button(role: .destructive) {
            pendingDelete = item
            showDeleteConfirm = true
        } label: {
            Label("Delete…", systemImage: "trash")
        }
        .disabled(busy)
    }

    private var emptyMessage: String {
        if !model.query.isEmpty {
            return "No items match \"\(model.query)\"."
        }
        return model.showArchived
            ? "No archived items."
            : "Promote something from DataPoints to see it here."
    }
}

private struct ItemRowView: View {
    @Environment(\.composerTypeface) private var typeface
    let item: ItemSummary
    let density: ListDensity

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xsmall) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(typeface.rowTitle)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(BackendDate.shortDate(item.publishedAt ?? item.promotedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let author = item.author, !author.isEmpty {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if density.showSummaryPreview, let summary = item.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, density.verticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts: [String] = [item.title]
        if let author = item.author, !author.isEmpty { parts.append(author) }
        if item.isArchived { parts.append("archived") }
        return parts.joined(separator: ", ")
    }
}
