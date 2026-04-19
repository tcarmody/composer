import SwiftUI

struct CollectionsListView: View {
    @ObservedObject var model: CollectionsModel
    @State private var isCreating = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            createBar
            Divider()
            list
        }
    }

    private var createBar: some View {
        Group {
            if isCreating {
                HStack(spacing: 6) {
                    TextField("Collection name", text: $newName, onCommit: submit)
                        .textFieldStyle(.roundedBorder)
                    Button("Add", action: submit)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") {
                        isCreating = false
                        newName = ""
                    }
                }
                .padding(10)
            } else {
                Button {
                    isCreating = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("New collection")
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
                .padding(10)
            }
        }
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
            if collections.isEmpty {
                ContentUnavailableView(
                    "No collections",
                    systemImage: "rectangle.stack",
                    description: Text("Create one to start gathering items and notes.")
                )
            } else {
                List(selection: Binding(
                    get: { model.selectedId },
                    set: { model.select($0) }
                )) {
                    ForEach(collections) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.system(size: 13, weight: .medium))
                            Text("\(c.memberCount) item\(c.memberCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(c.id)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func submit() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        model.create(name: trimmed)
        isCreating = false
        newName = ""
    }
}
