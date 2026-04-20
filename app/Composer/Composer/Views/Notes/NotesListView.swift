import SwiftUI

struct NotesListView: View {
    @ObservedObject var model: NotesModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.create()
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("New note")
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
            Divider()
            content
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
            if notes.isEmpty {
                ContentUnavailableView(
                    "No notes",
                    systemImage: "note.text",
                    description: Text("Create one to start writing.")
                )
            } else {
                List(selection: Binding(
                    get: { model.selectedId },
                    set: { model.select($0) }
                )) {
                    ForEach(notes) { note in
                        NoteRow(note: note).tag(note.id)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(displayTitle)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            if !previewBody.isEmpty {
                Text(previewBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(formatDateTime(note.updatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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
