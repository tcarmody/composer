import SwiftUI

struct CollectionDetailView: View {
    @ObservedObject var model: CollectionsModel
    @State private var showDeleteConfirm = false
    @State private var pendingDelete: Collection?

    var body: some View {
        switch model.detailState {
        case .empty:
            ContentUnavailableView(
                "Select a collection",
                systemImage: "rectangle.stack",
                description: Text("Pick a collection, or create a new one.")
            )
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let msg):
            ContentUnavailableView(
                "Failed to load",
                systemImage: "exclamationmark.triangle",
                description: Text(msg)
            )
        case .loaded(let outline):
            outlineView(outline)
                .confirmationDialog(
                    "Delete this collection?",
                    isPresented: $showDeleteConfirm,
                    presenting: pendingDelete
                ) { c in
                    Button("Delete", role: .destructive) { model.delete(c) }
                    Button("Cancel", role: .cancel) {}
                } message: { c in
                    Text("\"\(c.name)\" and its ordering will be removed. Items and notes themselves are preserved.")
                }
        }
    }

    @ViewBuilder
    private func outlineView(_ outline: Outline) -> some View {
        VStack(spacing: 0) {
            header(outline.collection)
            Divider()
            if outline.members.isEmpty {
                emptyState
            } else {
                membersList(outline.members)
            }
            Divider()
            InlineNoteComposer(onSubmit: { model.addInlineNote(body: $0) })
                .padding(16)
        }
    }

    private func header(_ collection: Collection) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name).font(.title2).bold()
                if let desc = collection.description, !desc.isEmpty {
                    Text(desc).font(.subheadline).foregroundStyle(.secondary)
                }
                Text("\(collection.memberCount) item\(collection.memberCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Delete", role: .destructive) {
                pendingDelete = collection
                showDeleteConfirm = true
            }
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack {
            Text("Empty collection.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Add items from the Library, or compose an inline note below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func membersList(_ members: [OutlineNode]) -> some View {
        List {
            ForEach(members) { node in
                OutlineNodeRow(node: node) {
                    model.removeMember(node)
                }
            }
            .onMove { from, to in
                model.reorder(from: from, to: to)
            }
        }
        .listStyle(.inset)
    }
}

private struct OutlineNodeRow: View {
    let node: OutlineNode
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kindLabel)
                    .font(.caption2).bold()
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                content
            }
            Spacer(minLength: 8)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from collection")
        }
        .padding(.vertical, 4)
    }

    private var kindLabel: String {
        switch node.memberType {
        case .item:
            if let item = node.item, item.archived { return "Item · archived" }
            return "Item"
        case .note: return "Note"
        case .draft: return "Draft"
        }
    }

    @ViewBuilder
    private var content: some View {
        if node.memberType == .item, let item = node.item {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? "(untitled)")
                    .font(.system(size: 13, weight: .medium))
                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } else if node.memberType == .note, let note = node.note {
            VStack(alignment: .leading, spacing: 3) {
                if let title = note.title, !title.isEmpty {
                    Text(title).font(.system(size: 13, weight: .medium))
                }
                Text(note.body)
                    .font(.body)
                    .textSelection(.enabled)
            }
        } else {
            Text("Unknown member").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct InlineNoteComposer: View {
    let onSubmit: (String) -> Void
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add inline note")
                .font(.caption).bold()
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Text("⌘-Return to submit")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add note") { submit() }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        text = ""
    }
}
