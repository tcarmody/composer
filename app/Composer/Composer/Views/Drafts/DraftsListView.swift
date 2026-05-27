import SwiftUI

struct DraftsListView: View {
    @ObservedObject var model: DraftsModel
    @EnvironmentObject private var app: AppState

    var body: some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { model.create() } label: {
                        Label("New Draft", systemImage: "square.and.pencil")
                    }
                    .help("New Draft (⌘N)")
                    .accessibilityLabel("New Draft")
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
        case .loaded(let drafts):
            let filtered = model.filteredDrafts(drafts)
            if filtered.isEmpty {
                ContentUnavailableView(
                    model.query.isEmpty ? "No drafts" : "No matches",
                    systemImage: "doc.text",
                    description: Text(emptyMessage(allEmpty: drafts.isEmpty))
                )
            } else {
                List(selection: Binding(
                    get: { model.selectedId },
                    set: { model.select($0) }
                )) {
                    ForEach(filtered) { draft in
                        DraftRow(draft: draft, density: app.listDensity).tag(draft.id)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func emptyMessage(allEmpty: Bool) -> String {
        if !model.query.isEmpty {
            return "No drafts match \"\(model.query)\"."
        }
        return allEmpty ? "Start one to write long-form." : "No drafts match your search."
    }
}

private struct DraftRow: View {
    let draft: Draft
    let density: ListDensity

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                StatusBadge(status: draft.status)
            }
            if density.showSummaryPreview, !previewBody.isEmpty {
                Text(previewBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(formatDateTime(draft.updatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, density.verticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayTitle), \(draft.status.label)")
    }

    private var displayTitle: String {
        if let t = draft.title, !t.isEmpty { return t }
        let first = draft.body.split(separator: "\n").first ?? ""
        let stripped = stripMarkdownPrefix(String(first))
        return stripped.isEmpty ? "Untitled draft" : stripped
    }

    private var previewBody: String {
        let lines = draft.body.split(separator: "\n")
        let skip = (draft.title?.isEmpty == false) ? 0 : 1
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

private struct StatusBadge: View {
    let status: DraftStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch status {
        case .wip: return Color.orange.opacity(0.18)
        case .final: return Color.green.opacity(0.18)
        }
    }

    private var foreground: Color {
        switch status {
        case .wip: return .orange
        case .final: return .green
        }
    }
}
