import SwiftUI

struct NotesListView: View {
    @ObservedObject var model: NotesModel
    @EnvironmentObject private var app: AppState

    var body: some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { model.create() } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                    .help("New Note (⌘N)")
                    .accessibilityLabel("New Note")
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.listState {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let msg):
            Text("Failed to load: \(msg)")
                .font(.caption)
                .foregroundStyle(.red)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .loaded(let notes):
            let filtered = model.filteredNotes(notes)
            if filtered.isEmpty {
                ContentUnavailableView(
                    model.query.isEmpty ? "No notes" : "No matches",
                    systemImage: "note.text",
                    description: Text(emptyMessage(allEmpty: notes.isEmpty))
                )
            } else {
                List(selection: Binding(
                    get: { model.selectedId },
                    set: { model.select($0) }
                )) {
                    ForEach(filtered) { note in
                        NoteRow(note: note, density: app.listDensity).tag(note.id)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func emptyMessage(allEmpty: Bool) -> String {
        if !model.query.isEmpty {
            return "No notes match \"\(model.query)\"."
        }
        return allEmpty ? "Create one to start writing." : "No notes match your search."
    }
}

private struct NoteRow: View {
    let note: Note
    let density: ListDensity

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(displayTitle)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            if density.showSummaryPreview, !previewBody.isEmpty {
                Text(previewBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(formatDateTime(note.updatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, density.verticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayTitle)
    }

    private var displayTitle: String {
        if let t = note.title, !t.isEmpty { return t }
        let first = note.body.split(separator: "\n").first ?? ""
        let stripped = stripMarkdownPrefix(String(first))
        return stripped.isEmpty ? "Untitled note" : stripped
    }

    private var previewBody: String {
        let lines = note.body.split(separator: "\n")
        let skip = (note.title?.isEmpty == false) ? 0 : 1
        return lines.dropFirst(skip).first.map { stripMarkdownPrefix(String($0)) } ?? ""
    }

    private func stripMarkdownPrefix(_ line: String) -> String {
        var s = line
        for prefix in ["### ", "## ", "# ", "> ", "- ", "* "] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
