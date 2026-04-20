import AppKit
import SwiftUI

struct RichTextEditor: NSViewRepresentable {
    @Binding var attributed: NSAttributedString
    var onCommand: ((Command) -> Void)?

    enum Command {
        case toggleBold, toggleItalic, toggleInlineCode, insertLink(URL)
        case setParagraph(ParagraphKind)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }

        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.font = Typography.font(for: .body)
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(attributed)
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        if context.coordinator.suppressExternalUpdate {
            context.coordinator.suppressExternalUpdate = false
            return
        }
        let current = textView.textStorage?.string ?? ""
        if current != attributed.string {
            let ranges = textView.selectedRanges
            textView.textStorage?.setAttributedString(attributed)
            textView.selectedRanges = ranges
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?
        var suppressExternalUpdate = false

        init(parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let storage = tv.textStorage else { return }
            suppressExternalUpdate = true
            parent.attributed = NSAttributedString(attributedString: storage)
        }

        func textViewDidChangeSelection(_ notification: Notification) {}
    }
}

@MainActor
final class RichTextCommands {
    weak var textView: NSTextView?

    func apply(_ command: RichTextEditor.Command) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let selection = tv.selectedRange()
        switch command {
        case .toggleBold:
            toggleFontTrait(.boldFontMask, in: selection, storage: storage, tv: tv)
        case .toggleItalic:
            toggleFontTrait(.italicFontMask, in: selection, storage: storage, tv: tv)
        case .toggleInlineCode:
            toggleInlineCode(in: selection, storage: storage, tv: tv)
        case .insertLink(let url):
            setLink(url, in: selection, storage: storage, tv: tv)
        case .setParagraph(let kind):
            setParagraphKind(kind, touching: selection, storage: storage, tv: tv)
        }
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask, in range: NSRange, storage: NSTextStorage, tv: NSTextView) {
        guard range.length > 0 else {
            var typing = tv.typingAttributes
            let baseFont = (typing[.font] as? NSFont) ?? Typography.font(for: .body)
            let current = NSFontManager.shared.traits(of: baseFont)
            let toggled: NSFont = current.contains(trait)
                ? NSFontManager.shared.convert(baseFont, toNotHaveTrait: trait)
                : NSFontManager.shared.convert(baseFont, toHaveTrait: trait)
            typing[.font] = toggled
            tv.typingAttributes = typing
            return
        }
        let allBold = rangeHasAllTrait(trait, range: range, storage: storage)
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? Typography.font(for: .body)
            let next: NSFont = allBold
                ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                : NSFontManager.shared.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: next, range: subrange)
        }
        storage.endEditing()
        tv.didChangeText()
    }

    private func rangeHasAllTrait(_ trait: NSFontTraitMask, range: NSRange, storage: NSTextStorage) -> Bool {
        var allSet = true
        storage.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
            let font = (value as? NSFont) ?? Typography.font(for: .body)
            if !NSFontManager.shared.traits(of: font).contains(trait) {
                allSet = false
                stop.pointee = true
            }
        }
        return allSet
    }

    private func toggleInlineCode(in range: NSRange, storage: NSTextStorage, tv: NSTextView) {
        guard range.length > 0 else { return }
        let allCode = rangeHasAllInlineCode(range: range, storage: storage)
        storage.beginEditing()
        if allCode {
            storage.removeAttribute(.inlineCode, range: range)
            storage.enumerateAttribute(.paragraphKind, in: range, options: []) { value, subrange, _ in
                let kind = (value as? String).flatMap(ParagraphKind.init) ?? .body
                storage.addAttribute(.font, value: Typography.font(for: kind), range: subrange)
            }
        } else {
            storage.addAttribute(.inlineCode, value: true, range: range)
            storage.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: Typography.bodySize, weight: .regular),
                range: range
            )
        }
        storage.endEditing()
        tv.didChangeText()
    }

    private func rangeHasAllInlineCode(range: NSRange, storage: NSTextStorage) -> Bool {
        var all = true
        storage.enumerateAttribute(.inlineCode, in: range, options: []) { value, _, stop in
            if (value as? Bool) != true {
                all = false
                stop.pointee = true
            }
        }
        return all
    }

    private func setLink(_ url: URL, in range: NSRange, storage: NSTextStorage, tv: NSTextView) {
        guard range.length > 0 else { return }
        storage.beginEditing()
        storage.addAttribute(.link, value: url, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
        storage.endEditing()
        tv.didChangeText()
    }

    private func setParagraphKind(_ kind: ParagraphKind, touching range: NSRange, storage: NSTextStorage, tv: NSTextView) {
        let paragraphs = (storage.string as NSString).paragraphRange(for: range)
        let font = Typography.font(for: kind)
        let style = Typography.paragraphStyle(for: kind)
        storage.beginEditing()
        storage.addAttributes([
            .paragraphKind: kind.rawValue,
            .paragraphStyle: style,
            .font: font
        ], range: paragraphs)
        storage.enumerateAttribute(.font, in: paragraphs, options: []) { value, subrange, _ in
            let existing = (value as? NSFont) ?? font
            let traits = NSFontManager.shared.traits(of: existing)
            var next = font
            if traits.contains(.boldFontMask) {
                next = NSFontManager.shared.convert(next, toHaveTrait: .boldFontMask)
            }
            if traits.contains(.italicFontMask) {
                next = NSFontManager.shared.convert(next, toHaveTrait: .italicFontMask)
            }
            storage.addAttribute(.font, value: next, range: subrange)
        }
        storage.endEditing()
        tv.didChangeText()
    }
}
