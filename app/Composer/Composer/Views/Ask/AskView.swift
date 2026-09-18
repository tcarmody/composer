import SwiftUI

struct AskView: View {
    @StateObject private var model: AskModel
    @EnvironmentObject private var app: AppState

    init(api: APIClient) {
        _model = StateObject(wrappedValue: AskModel(api: api))
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                // The transcript takes the slack so the input bar stays pinned
                // to the bottom. Without it HSplitView sizes to content and
                // both columns float in the middle of the window.
                AskTranscriptView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                AskInputBar(model: model)
            }
            .frame(minWidth: 420, maxHeight: .infinity)
            .composerSurface(.reading)

            AskCitationsView(model: model, onOpenSource: openSource)
                .frame(minWidth: 260, idealWidth: 320, maxHeight: .infinity)
                .composerSurface(.chrome)
        }
        .focusedSceneValue(\.refreshAction, RefreshAction {
            model.reset()
        })
    }

    private func openSource(_ citation: Citation) {
        switch citation.sourceType {
        case "item": app.openItem(id: citation.sourceId)
        case "note": app.openNote(id: citation.sourceId)
        case "draft": app.openDraft(id: citation.sourceId)
        default: break
        }
    }
}

private struct AskInputBar: View {
    @ObservedObject var model: AskModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(spacing: Spacing.small) {
                Picker("Scope", selection: $model.scope) {
                    ForEach(SourceFilter.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(model.isStreaming)

                TextField(
                    "Ask a question about your archive…",
                    text: $model.input,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onSubmit { model.ask() }
                .disabled(model.isStreaming)

                if model.isStreaming {
                    Button("Stop", role: .destructive) { model.cancel() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button("Ask") { model.ask() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canAsk)
                }
            }
        }
        .padding(Spacing.medium)
        .onAppear { inputFocused = true }
    }
}
