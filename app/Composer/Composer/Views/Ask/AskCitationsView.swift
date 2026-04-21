import SwiftUI

struct AskCitationsView: View {
    @ObservedObject var model: AskModel

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
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            .padding(12)

            Divider()

            if model.citations.isEmpty {
                emptyState
            } else {
                List(model.citations, selection: $model.selectedCitationId) { citation in
                    CitationRow(citation: citation)
                        .tag(citation.id)
                }
                .listStyle(.sidebar)
            }

            if !model.citations.isEmpty {
                Divider()
                HStack(spacing: 4) {
                    Image(systemName: model.vectorSearchUsed ? "circle.fill" : "circle")
                        .font(.system(size: 7))
                        .foregroundStyle(model.vectorSearchUsed ? .green : .secondary)
                    Text(model.vectorSearchUsed ? "Hybrid search" : "BM25 only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No sources yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Ask a question to see cited passages.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }
}

private struct CitationRow: View {
    let citation: Citation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("[\(citation.index)]")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(citation.sourceTitle ?? "Untitled")
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
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
        .padding(.vertical, 4)
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
