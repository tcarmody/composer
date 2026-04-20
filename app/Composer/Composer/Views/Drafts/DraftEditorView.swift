import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
            Menu {
                Button("Markdown (.md)") { exportMarkdown(draft: draft) }
                Button("HTML (.html)") { exportHTML(draft: draft) }
                Button("Copy HTML to Clipboard") { copyHTML(draft: draft) }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button("Delete", role: .destructive) { showDeleteConfirm = true }
        }
        .padding(16)
    }

    private func filename(for draft: Draft, ext: String) -> String {
        let base = (draft.title?.isEmpty == false ? draft.title! : "Untitled")
        let safe = base.replacingOccurrences(
            of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
        return (safe.isEmpty ? "Untitled" : safe) + "." + ext
    }

    private func exportMarkdown(draft: Draft) {
        let markdown = MarkdownConverter.markdown(from: model.editorAttributed)
        let body: String
        if let t = draft.title, !t.isEmpty, !markdown.hasPrefix("# ") {
            body = "# \(t)\n\n\(markdown)"
        } else {
            body = markdown
        }
        savePanel(
            suggested: filename(for: draft, ext: "md"),
            type: UTType(filenameExtension: "md") ?? .plainText,
            contents: body
        )
    }

    private func exportHTML(draft: Draft) {
        let markdown = MarkdownConverter.markdown(from: model.editorAttributed)
        let html = MarkdownExporter.html(from: markdown, title: draft.title)
        savePanel(
            suggested: filename(for: draft, ext: "html"),
            type: .html,
            contents: html
        )
    }

    private func copyHTML(draft: Draft) {
        let markdown = MarkdownConverter.markdown(from: model.editorAttributed)
        let html = MarkdownExporter.htmlBody(from: markdown)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(html, forType: .html)
        pb.setString(html, forType: .string)
    }

    private func savePanel(suggested: String, type: UTType, contents: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? contents.write(to: url, atomically: true, encoding: .utf8)
        }
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
