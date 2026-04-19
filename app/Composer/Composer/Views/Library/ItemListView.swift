import SwiftUI

struct ItemListView: View {
    @ObservedObject var model: LibraryModel

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            content
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            TextField("Search items…", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.query) { _, _ in model.scheduleSearch() }

            Picker("", selection: $model.showArchived) {
                Text("Active").tag(false)
                Text("Archived").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: model.showArchived) { _, _ in model.refreshList() }
        }
        .padding(10)
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
                            ItemRowView(item: item)
                                .tag(item.id)
                        }
                    } header: {
                        Text("\(response.total) item\(response.total == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
            }
        }
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
    let item: ItemSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(formatDate(item.publishedAt ?? item.promotedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let author = item.author, !author.isEmpty {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let summary = item.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

func formatDate(_ iso: String?) -> String {
    guard let iso, !iso.isEmpty else { return "" }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
    let fallback = DateFormatter()
    fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
    if let d = fallback.date(from: iso) {
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
    return iso
}

func formatDateTime(_ iso: String?) -> String {
    guard let iso, !iso.isEmpty else { return "" }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
        return d.formatted(date: .abbreviated, time: .shortened)
    }
    let fallback = DateFormatter()
    fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
    if let d = fallback.date(from: iso) {
        return d.formatted(date: .abbreviated, time: .shortened)
    }
    return iso
}
