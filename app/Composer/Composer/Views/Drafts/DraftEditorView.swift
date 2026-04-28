import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DraftEditorView: View {
    @ObservedObject var model: DraftsModel
    var isCompact: Bool = false
    @EnvironmentObject private var app: AppState
    @StateObject private var commands = RichTextCommandsHolder()
    @State private var showLinkSheet = false
    @State private var linkURLDraft = ""
    @State private var showDeleteConfirm = false
    @State private var showSourcesPopover = false

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
        HStack(spacing: 0) {
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
                RichTextEditorHosted(
                    attributed: $model.editorAttributed,
                    commands: commands,
                    theme: app.theme,
                    menuBuilder: factCheckMenuItems
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !isFactCheckIdle {
                Divider()
                FactCheckPanel(model: model, onLocate: locateClaim)
            }
        }
        .background(app.theme.backgroundColor)
        .foregroundStyle(app.theme.textColor, app.theme.secondaryTextColor)
        .tint(app.theme.accentColor)
    }

    private var isFactCheckIdle: Bool {
        if case .idle = model.factCheckPhase { return true } else { return false }
    }

    private func factCheckMenuItems(for range: NSRange) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if range.length > 0,
           let storage = commands.store.textView?.textStorage {
            let captured = storage.attributedSubstring(from: range).string
            items.append(ClosureMenuItem(title: "Fact-check selection") { [weak model] in
                model?.startFactCheck(selection: captured)
            })
        }
        items.append(ClosureMenuItem(title: "Fact-check entire draft") { [weak model] in
            model?.startFactCheck(selection: nil)
        })
        return items
    }

    private func locateClaim(_ claim: String) {
        guard let tv = commands.store.textView else { return }
        let haystack = tv.string as NSString
        let found = haystack.range(of: claim)
        guard found.location != NSNotFound else {
            NSSound.beep()
            return
        }
        tv.window?.makeFirstResponder(tv)
        tv.setSelectedRange(found)
        tv.scrollRangeToVisible(found)
    }

    private var hasSelection: Bool {
        (commands.store.textView?.selectedRange().length ?? 0) > 0
    }

    private func runFactCheck(useSelection: Bool) {
        var selectionText: String? = nil
        if useSelection,
           let tv = commands.store.textView,
           let storage = tv.textStorage,
           tv.selectedRange().length > 0 {
            selectionText = storage.attributedSubstring(from: tv.selectedRange()).string
        }
        model.startFactCheck(selection: selectionText)
    }

    @ViewBuilder
    private func titleBar(draft: Draft) -> some View {
        if isCompact {
            compactTitleBar(draft: draft)
        } else {
            fullTitleBar(draft: draft)
        }
    }

    private func fullTitleBar(draft: Draft) -> some View {
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
            sourcesButton
            Button("Save") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.isDirty)
            Menu {
                Section("AI") {
                    ForEach(DraftAssistAction.allCases, id: \.self) { action in
                        Button(action.label) { runAssist(action) }
                    }
                }
                Section("Fact-check") {
                    Button("Fact-check selection") { runFactCheck(useSelection: true) }
                        .disabled(!hasSelection)
                    Button("Fact-check entire draft") { runFactCheck(useSelection: false) }
                }
                Section("Format") {
                    Button("Convert straight quotes to smart quotes") { applySmartQuotes() }
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
        .background(app.theme.chromeBackground)
    }

    private func compactTitleBar(draft: Draft) -> some View {
        HStack(spacing: 8) {
            TextField("Untitled", text: $model.titleDraft, onEditingChanged: { _ in model.titleChanged() })
                .textFieldStyle(.plain)
                .font(.headline)
            Circle()
                .fill(model.isDirty ? Color.orange : Color.clear)
                .frame(width: 6, height: 6)
                .help(model.isDirty ? "Unsaved changes" : "Saved")
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
            sourcesButton
            Menu {
                Section("Assist") {
                    ForEach(DraftAssistAction.allCases, id: \.self) { action in
                        Button(action.label) { runAssist(action) }
                    }
                }
                Section("Fact-check") {
                    Button("Fact-check selection") { runFactCheck(useSelection: true) }
                        .disabled(!hasSelection)
                    Button("Fact-check entire draft") { runFactCheck(useSelection: false) }
                }
                Section("Format") {
                    Button("Convert straight quotes to smart quotes") { applySmartQuotes() }
                }
                Section("Export") {
                    Button("Markdown (.md)") { exportMarkdown(draft: draft) }
                    Button("HTML (.html)") { exportHTML(draft: draft) }
                    Button("Copy HTML to Clipboard") { copyHTML(draft: draft) }
                }
                Section {
                    Button("Save", action: { model.save() })
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!model.isDirty)
                    Button("Delete", role: .destructive) { showDeleteConfirm = true }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(app.theme.chromeBackground)
    }

    @ViewBuilder
    private var sourcesButton: some View {
        if !model.sources.isEmpty {
            Button {
                showSourcesPopover.toggle()
            } label: {
                Label("\(model.sources.count)", systemImage: "link")
            }
            .buttonStyle(.borderless)
            .help("Sources composing this draft")
            .popover(isPresented: $showSourcesPopover, arrowEdge: .bottom) {
                sourcesPopoverContent
            }
        }
    }

    private var sourcesPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sources")
                    .font(.headline)
                Spacer()
                Text("\(model.sources.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(uniqueSources()) { row in
                        sourceRow(row)
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(width: 360, height: min(400, CGFloat(60 + uniqueSources().count * 70)))
    }

    private struct GroupedSource: Identifiable {
        let id: String   // item_id
        let title: String?
        let author: String?
        let url: String?
        let sources: [DraftSource]
    }

    private func uniqueSources() -> [GroupedSource] {
        let dict = Dictionary(grouping: model.sources, by: { $0.itemId })
        return dict
            .map { (itemId, group) in
                let first = group.first
                return GroupedSource(
                    id: itemId,
                    title: first?.itemTitle,
                    author: first?.itemAuthor,
                    url: first?.itemUrl,
                    sources: group
                )
            }
            .sorted { ($0.sources.first?.addedAt ?? "") < ($1.sources.first?.addedAt ?? "") }
    }

    private func sourceRow(_ group: GroupedSource) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    app.openItem(id: group.id)
                    showSourcesPopover = false
                } label: {
                    Text(group.title ?? "(untitled)")
                        .font(.subheadline).bold()
                        .lineLimit(1)
                }
                .buttonStyle(.link)
                Spacer(minLength: 8)
                Text("\(group.sources.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let author = group.author, !author.isEmpty {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Remove all", role: .destructive) {
                    for s in group.sources { model.removeSource(s) }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(.caption2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

    private func applySmartQuotes() {
        guard let tv = commands.store.textView, let storage = tv.textStorage else { return }
        let selection = tv.selectedRange()
        let target: NSRange = selection.length > 0
            ? selection
            : NSRange(location: 0, length: storage.length)
        let changes = SmartQuotes.convertInPlace(storage, range: target)
        guard changes > 0 else { return }
        tv.didChangeText()
        tv.setSelectedRange(target)
        model.editorAttributed = NSAttributedString(attributedString: storage)
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
