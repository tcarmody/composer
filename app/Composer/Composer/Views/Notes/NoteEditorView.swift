import AppKit
import SwiftUI

struct NoteEditorView: View {
    @ObservedObject var model: NotesModel
    @EnvironmentObject private var app: AppState
    @StateObject private var commands = RichTextCommandsHolder()
    @State private var showLinkSheet = false
    @State private var linkURLDraft = ""

    var body: some View {
        Group {
            switch model.editorState {
            case .empty:
                ContentUnavailableView(
                    "Select a note",
                    systemImage: "note.text",
                    description: Text("Pick a note from the list, or create a new one.")
                )
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let msg):
                ContentUnavailableView(
                    "Failed to load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(msg)
                )
            case .editing(let note, _, _):
                editor(note: note)
                    .sheet(isPresented: $showLinkSheet) { linkSheet }
            }
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { model.pendingDelete != nil },
                set: { if !$0 { model.pendingDelete = nil } }
            ),
            presenting: model.pendingDelete
        ) { note in
            Button("Delete", role: .destructive) {
                model.delete(note)
                model.pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                model.pendingDelete = nil
            }
        } message: { _ in
            Text("The note will be removed permanently.")
        }
    }

    private func editor(note: Note) -> some View {
        VStack(spacing: 0) {
            titleBar(note: note)
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
            RichTextEditorHosted(attributed: $model.editorAttributed, commands: commands, theme: app.theme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(app.theme.backgroundColor)
        .foregroundStyle(app.theme.textColor, app.theme.secondaryTextColor)
        .tint(app.theme.accentColor)
        .navigationSubtitle(model.isDirty ? "Unsaved changes" : "")
    }

    private func titleBar(note: Note) -> some View {
        HStack(spacing: 12) {
            TextField("Untitled", text: $model.titleDraft, onEditingChanged: { _ in model.titleChanged() })
                .textFieldStyle(.plain)
                .font(.title2).bold()
                .accessibilityLabel("Note title")
            Spacer()
            if model.isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .help("Unsaved changes")
                    .accessibilityLabel("Unsaved changes")
            }
        }
        .padding(16)
        .background(app.theme.chromeBackground)
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

@MainActor
final class RichTextCommandsHolder: ObservableObject {
    let store = RichTextCommands()
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        self.target = self
    }
    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }
    @objc private func invoke() { handler() }
}

struct RichTextEditorHosted: NSViewRepresentable {
    @Binding var attributed: NSAttributedString
    let commands: RichTextCommandsHolder
    var theme: AppTheme = .auto
    var menuBuilder: ((NSRange) -> [NSMenuItem])? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isRichText = true
        tv.isEditable = true
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.textContainerInset = NSSize(width: 12, height: 16)
        tv.font = Typography.font(for: .body)
        tv.textStorage?.setAttributedString(attributed)
        tv.delegate = context.coordinator
        context.coordinator.textView = tv
        commands.store.textView = tv
        applyTheme(to: tv, scroll: scroll)
        context.coordinator.lastTheme = theme
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        commands.store.textView = tv
        if context.coordinator.lastTheme != theme {
            applyTheme(to: tv, scroll: scroll)
            context.coordinator.lastTheme = theme
        }
        if context.coordinator.suppressExternal {
            context.coordinator.suppressExternal = false
            return
        }
        if tv.textStorage?.string != attributed.string {
            let ranges = tv.selectedRanges
            tv.textStorage?.setAttributedString(attributed)
            tv.selectedRanges = ranges
        }
    }

    private func applyTheme(to tv: NSTextView, scroll: NSScrollView) {
        let bg = NSColor(theme.backgroundColor)
        let fg = NSColor(theme.textColor)
        tv.textColor = fg
        tv.backgroundColor = bg
        tv.insertionPointColor = NSColor(theme.accentColor)
        scroll.drawsBackground = true
        scroll.backgroundColor = bg
        tv.linkTextAttributes = [
            .foregroundColor: NSColor(theme.accentColor),
            .cursor: NSCursor.pointingHand,
        ]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditorHosted
        weak var textView: NSTextView?
        var suppressExternal = false
        var lastTheme: AppTheme?

        init(parent: RichTextEditorHosted) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let storage = tv.textStorage else { return }
            suppressExternal = true
            parent.attributed = NSAttributedString(attributedString: storage)
        }

        func textView(
            _ view: NSTextView,
            menu: NSMenu,
            for event: NSEvent,
            at charIndex: Int
        ) -> NSMenu? {
            guard let builder = parent.menuBuilder else { return menu }
            let selected = view.selectedRange()
            let target: NSRange
            if selected.length > 0,
               NSLocationInRange(charIndex, selected) {
                target = selected
            } else {
                target = NSRange(location: charIndex, length: 0)
            }
            let extras = builder(target)
            guard !extras.isEmpty else { return menu }
            for (i, item) in extras.enumerated() {
                menu.insertItem(item, at: i)
            }
            menu.insertItem(NSMenuItem.separator(), at: extras.count)
            return menu
        }
    }
}
