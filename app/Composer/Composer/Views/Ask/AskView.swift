import SwiftUI

struct AskView: View {
    @StateObject private var model: AskModel

    init(api: APIClient) {
        _model = StateObject(wrappedValue: AskModel(api: api))
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                AskTranscriptView(model: model)
                Divider()
                AskInputBar(model: model)
            }
            .frame(minWidth: 420)

            AskCitationsView(model: model)
                .frame(minWidth: 260, idealWidth: 320)
        }
        .focusedSceneValue(\.refreshAction, RefreshAction {
            model.reset()
        })
    }
}

private struct AskInputBar: View {
    @ObservedObject var model: AskModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
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
        .padding(12)
        .onAppear { inputFocused = true }
    }
}
