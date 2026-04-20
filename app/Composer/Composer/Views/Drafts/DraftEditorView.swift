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
                .sheet(isPresented: Binding(
                    get: { isAssistSheetVisible },
                    set: { if !$0 { model.dismissAssist() } }
                )) { assistSheet }
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

    private var isAssistSheetVisible: Bool {
        switch model.assistState {
        case .idle: return false
        default: return true
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
                ForEach(DraftAssistAction.allCases, id: \.self) { action in
                    Button(action.label) { runAssist(action) }
                }
            } label: {
                Label("Assist", systemImage: "sparkles")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
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

    private func runAssist(_ action: DraftAssistAction) {
        let tv = commands.store.textView
        let storage = tv?.textStorage
        let range = tv?.selectedRange() ?? NSRange(location: 0, length: 0)
        let selectionText: String? = {
            guard let storage, range.length > 0 else { return nil }
            return storage.attributedSubstring(from: range).string
        }()
        let fullRange = NSRange(location: 0, length: storage?.length ?? 0)
        let targetRange = range.length > 0 ? range : fullRange
        model.runAssist(action: action, selection: targetRange, selectionText: selectionText)
    }

    @ViewBuilder
    private var assistSheet: some View {
        switch model.assistState {
        case .idle:
            EmptyView()
        case .running(let action):
            VStack(spacing: 16) {
                ProgressView()
                Text("\(action.label) in progress…").font(.headline)
                Text(action.description).font(.caption).foregroundStyle(.secondary)
                Button("Cancel") { model.dismissAssist() }
            }
            .padding(32)
            .frame(minWidth: 360)
        case .error(let msg):
            VStack(alignment: .leading, spacing: 12) {
                Label("Assist failed", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(msg).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Dismiss") { model.dismissAssist() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(minWidth: 420)
        case .ready(let action, let selection, let suggestion):
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(action.label, systemImage: "sparkles").font(.headline)
                    Spacer()
                }
                Text(action.description).font(.caption).foregroundStyle(.secondary)
                Divider()
                ScrollView {
                    Text(suggestion)
                        .font(.system(.body, design: .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 520, minHeight: 220, idealHeight: 360)
                HStack {
                    Button("Copy") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(suggestion, forType: .string)
                    }
                    Spacer()
                    Button("Cancel") { model.dismissAssist() }
                    Button("Replace") { accept(suggestion: suggestion, range: selection) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
    }

    private func accept(suggestion: String, range: NSRange) {
        guard let tv = commands.store.textView,
              let storage = tv.textStorage else {
            model.dismissAssist()
            return
        }
        let replacement = MarkdownConverter.attributedString(from: suggestion)
        let safe = NSRange(
            location: min(range.location, storage.length),
            length: min(range.length, max(0, storage.length - range.location))
        )
        storage.replaceCharacters(in: safe, with: replacement)
        let newLen = (replacement.string as NSString).length
        tv.setSelectedRange(NSRange(location: safe.location, length: newLen))
        model.editorAttributed = NSAttributedString(attributedString: storage)
        model.dismissAssist()
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
