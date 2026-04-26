import AppKit
import SwiftUI

struct RichContentView: NSViewRepresentable {
    let content: String
    var theme: AppTheme = .auto
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
        applyTheme(to: tv)
        render(into: tv)
        return tv
    }

    func updateNSView(_ tv: IntrinsicTextView, context: Context) {
        tv.onQuote = onQuote
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
        let noteItem = NSMenuItem(
            title: "Quote as Note",
            action: #selector(quoteAsNote(_:)),
            keyEquivalent: ""
        )
        noteItem.target = self
        let draftItem = NSMenuItem(
            title: "Quote as Draft",
            action: #selector(quoteAsDraft(_:)),
            keyEquivalent: ""
        )
        draftItem.target = self
        menu.insertItem(noteItem, at: 0)
        menu.insertItem(draftItem, at: 1)
        menu.insertItem(.separator(), at: 2)
        return menu
    }

    @objc private func quoteAsNote(_ sender: Any?) {
        emitQuote(.note)
    }

    @objc private func quoteAsDraft(_ sender: Any?) {
        emitQuote(.draft)
    }

    private func emitQuote(_ kind: QuoteKind) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        guard range.length > 0 else { return }
        let text = storage.attributedSubstring(from: range).string
        onQuote?(kind, text)
    }
}
