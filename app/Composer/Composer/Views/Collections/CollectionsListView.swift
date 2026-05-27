import SwiftUI

struct CollectionsListView: View {
    @ObservedObject var model: CollectionsModel
    @EnvironmentObject private var app: AppState
    @State private var newName = ""

    var body: some View {
        list
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { model.isCreating = true } label: {
                        Label("New Collection", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .help("New Collection (⌘N)")
                    .accessibilityLabel("New Collection")
                }
            }
            .sheet(isPresented: $model.isCreating, onDismiss: { newName = "" }) {
                newCollectionSheet
            }
    }

    private var newCollectionSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New collection").font(.headline)
            TextField("Collection name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 320)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel") {
                    model.isCreating = false
                    newName = ""
                }
                .keyboardShortcut(.cancelAction)
                Button("Add") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var list: some View {
        switch model.listState {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let msg):
            Text("Failed to load: \(msg)")
                .font(.caption)
                .foregroundStyle(.red)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .loaded(let collections):
            let filtered = model.filteredCollections(collections)
            if filtered.isEmpty {
                ContentUnavailableView(
                    model.query.isEmpty ? "No collections" : "No matches",
                    systemImage: "rectangle.stack",
                    description: Text(emptyMessage(allEmpty: collections.isEmpty))
                )
            } else {
                List(selection: Binding(
                    get: { model.selectedId },
                    set: { model.select($0) }
                )) {
                    ForEach(filtered) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.system(size: 13, weight: .medium))
                            Text("\(c.memberCount) item\(c.memberCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, app.listDensity.verticalPadding)
                        .tag(c.id)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(c.name), \(c.memberCount) item\(c.memberCount == 1 ? "" : "s")")
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func emptyMessage(allEmpty: Bool) -> String {
        if !model.query.isEmpty {
            return "No collections match \"\(model.query)\"."
        }
        return allEmpty ? "Create one to start gathering items and notes." : "No collections match your search."
    }

    private func submit() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        model.create(name: trimmed)
        model.isCreating = false
        newName = ""
    }
}
