import AppKit
import SwiftUI

struct RichContentView: NSViewRepresentable {
    let content: String
    var theme: AppTheme = .auto
    var hasCurrentDraft: Bool = false
    var onQuote: ((QuoteKind, String) -> Void)? = nil

    func makeNSView(context: Context) -> IntrinsicTextView {
        let tv = IntrinsicTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.onQuote = onQuote
        tv.hasCurrentDraft = hasCurrentDraft
        applyTheme(to: tv)
        render(into: tv)
        return tv
    }

    func updateNSView(_ tv: IntrinsicTextView, context: Context) {
        tv.onQuote = onQuote
        tv.hasCurrentDraft = hasCurrentDraft
        let themeChanged = tv.lastRenderedTheme != theme
        if themeChanged {
            applyTheme(to: tv)
        }
        if tv.lastRenderedContent != content || themeChanged {
            render(into: tv)
        }
    }

    private func applyTheme(to tv: IntrinsicTextView) {
        tv.textColor = NSColor(theme.textColor)
        tv.linkTextAttributes = [
            .foregroundColor: NSColor(theme.accentColor),
            .cursor: NSCursor.pointingHand,
        ]
    }

    private func render(into tv: IntrinsicTextView) {
        let attr = RichContentRenderer.render(content)
            .applying(textColor: NSColor(theme.textColor))
        tv.textStorage?.setAttributedString(attr)
        tv.lastRenderedContent = content
        tv.lastRenderedTheme = theme
        tv.invalidateIntrinsicContentSize()
    }
}

private extension NSAttributedString {
    func applying(textColor: NSColor) -> NSAttributedString {
        let mut = NSMutableAttributedString(attributedString: self)
        let full = NSRange(location: 0, length: mut.length)
        mut.enumerateAttribute(.link, in: full, options: []) { link, range, _ in
            guard link == nil else { return }
            mut.removeAttribute(.foregroundColor, range: range)
            mut.addAttribute(.foregroundColor, value: textColor, range: range)
        }
        return mut
    }
}

final class IntrinsicTextView: NSTextView {
    var lastRenderedContent: String?
    var lastRenderedTheme: AppTheme?
    var onQuote: ((QuoteKind, String) -> Void)?
    var hasCurrentDraft: Bool = false

    override var intrinsicContentSize: NSSize {
        guard let lm = layoutManager, let tc = textContainer else {
            return super.intrinsicContentSize
        }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(used.height))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard onQuote != nil, selectedRange().length > 0 else { return menu }
        var idx = 0
        if hasCurrentDraft {
            let appendItem = NSMenuItem(
                title: "Append to Current Draft",
                action: #selector(appendToCurrentDraft(_:)),
                keyEquivalent: ""
            )
            appendItem.target = self
            menu.insertItem(appendItem, at: idx); idx += 1
        }
        let noteItem = NSMenuItem(
            title: "Quote as Note",
            action: #selector(quoteAsNote(_:)),
            keyEquivalent: ""
        )
        noteItem.target = self
        menu.insertItem(noteItem, at: idx); idx += 1
        let draftItem = NSMenuItem(
            title: hasCurrentDraft ? "Quote as New Draft" : "Quote as Draft",
            action: #selector(quoteAsDraft(_:)),
            keyEquivalent: ""
        )
        draftItem.target = self
        menu.insertItem(draftItem, at: idx); idx += 1
        menu.insertItem(.separator(), at: idx)
        return menu
    }

    @objc private func quoteAsNote(_ sender: Any?) {
        emitQuote(.note)
    }

    @objc private func quoteAsDraft(_ sender: Any?) {
        emitQuote(.draft)
    }

    @objc private func appendToCurrentDraft(_ sender: Any?) {
        emitQuote(.appendToDraft)
    }

    private func emitQuote(_ kind: QuoteKind) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        guard range.length > 0 else { return }
        let text = storage.attributedSubstring(from: range).string
        onQuote?(kind, text)
    }
}
