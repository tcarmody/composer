import AppKit
import SwiftUI

struct DraftEditorView: View {
    @ObservedObject var model: DraftsModel
    @StateObject private var commands = RichTextCommandsHolder()
    @State private var showLinkSheet = false
    @State private var linkURLDraft = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        switch model.editorState {
        case .empty:
            ContentUnavailableView(
                "Select a draft",
                systemImage: "doc.text",
                description: Text("Pick a draft from the list, or start a new one.")
            )
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let msg):
            ContentUnavailableView(
                "Failed to load",
                systemImage: "exclamationmark.triangle",
                description: Text(msg)
            )
        case .editing(let draft, _, _):
            editor(draft: draft)
                .sheet(isPresented: $showLinkSheet) { linkSheet }
                .confirmationDialog(
                    "Delete this draft?",
                    isPresented: $showDeleteConfirm
                ) {
                    Button("Delete", role: .destructive) { model.delete(draft) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The draft will be removed permanently.")
                }
        }
    }

    private func editor(draft: Draft) -> some View {
        VStack(spacing: 0) {
            titleBar(draft: draft)
            Divider()
            RichTextToolbar(
                onBold: { commands.store.apply(.toggleBold) },
                onItalic: { commands.store.apply(.toggleItalic) },
                onCode: { commands.store.apply(.toggleInlineCode) },
                onHeading: { level in
                    let kind: ParagraphKind = level == 1 ? .heading1 : level == 2 ? .heading2 : .heading3
                    commands.store.apply(.setParagraph(kind))
                },
                onBullet: { commands.store.apply(.setParagraph(.bullet)) },
                onNumbered: { commands.store.apply(.setParagraph(.numbered)) },
                onQuote: { commands.store.apply(.setParagraph(.blockquote)) },
                onBody: { commands.store.apply(.setParagraph(.body)) },
                onLink: { showLinkSheet = true }
            )
            Divider()
            RichTextEditorHosted(attributed: $model.editorAttributed, commands: commands)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func titleBar(draft: Draft) -> some View {
        HStack(spacing: 12) {
            TextField("Untitled", text: $model.titleDraft, onEditingChanged: { _ in model.titleChanged() })
                .textFieldStyle(.plain)
                .font(.title2).bold()
            Picker("", selection: Binding(
                get: { model.statusDraft },
                set: { model.statusDraft = $0; model.statusChanged() }
            )) {
                ForEach(DraftStatus.allCases, id: \.self) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer()
            Text(model.isDirty ? "Unsaved changes" : "Saved")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Save") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.isDirty)
            Button("Delete", role: .destructive) { showDeleteConfirm = true }
        }
        .padding(16)
    }

    private var linkSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insert link").font(.headline)
            TextField("https://…", text: $linkURLDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)
            HStack {
                Spacer()
                Button("Cancel") { showLinkSheet = false }
                Button("Apply") {
                    if let url = URL(string: linkURLDraft), !linkURLDraft.isEmpty {
                        commands.store.apply(.insertLink(url))
                    }
                    showLinkSheet = false
                    linkURLDraft = ""
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
