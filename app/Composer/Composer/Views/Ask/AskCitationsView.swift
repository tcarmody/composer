import SwiftUI

struct AskCitationsView: View {
    @ObservedObject var model: AskModel
    let onOpenSource: (Citation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sources")
                    .font(.headline)
                Spacer()
                if !model.citations.isEmpty {
                    Text("\(model.citations.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Spacing.small)
                        .padding(.vertical, Spacing.tight)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            .padding(Spacing.medium)

            Divider()

            if model.citations.isEmpty {
                emptyState
            } else {
                List(model.citations, selection: $model.selectedCitationId) { citation in
                    CitationRow(citation: citation, onOpen: { onOpenSource(citation) })
                        .tag(citation.id)
                }
                .listStyle(.sidebar)
            }

            if !model.citations.isEmpty {
                Divider()
                HStack(spacing: Spacing.xsmall) {
                    Image(systemName: model.vectorSearchUsed ? "circle.fill" : "circle")
                        .font(.system(size: 7))
                        .foregroundStyle(model.vectorSearchUsed ? .green : .secondary)
                    Text(model.vectorSearchUsed ? "Hybrid search" : "BM25 only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
            }
        }
    }

    private var emptyState: some View {
        // Greedy on purpose. As a plain VStack child it sizes to its content
        // and the whole column — header included — floats to the middle.
        ContentUnavailableView(
            "No sources yet",
            systemImage: "books.vertical",
            description: Text("Ask a question to see cited passages.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CitationRow: View {
    let citation: Citation
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xsmall) {
            HStack(spacing: Spacing.small) {
                Text("[\(citation.index)]")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(citation.sourceTitle ?? "Untitled")
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Open source")
                .accessibilityLabel("Open source")
            }
            Text(citation.snippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            if let url = citation.sourceURL, let parsed = URL(string: url) {
                Link(destination: parsed) {
                    Text(displayURL(url))
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, Spacing.xsmall)
    }

    private var icon: String {
        switch citation.sourceType {
        case "item": return "doc.richtext"
        case "note": return "note.text"
        case "draft": return "doc.text"
        default: return "doc"
        }
    }

    private func displayURL(_ url: String) -> String {
        guard let host = URL(string: url)?.host else { return url }
        return host
    }
}
