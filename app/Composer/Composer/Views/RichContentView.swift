import AppKit
import SwiftUI

struct RichContentView: NSViewRepresentable {
    let content: String

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
        tv.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .cursor: NSCursor.pointingHand,
        ]
        render(into: tv)
        return tv
    }

    func updateNSView(_ tv: IntrinsicTextView, context: Context) {
        if tv.lastRenderedContent != content {
            render(into: tv)
        }
    }

    private func render(into tv: IntrinsicTextView) {
        let attr = RichContentRenderer.render(content)
        tv.textStorage?.setAttributedString(attr)
        tv.lastRenderedContent = content
        tv.invalidateIntrinsicContentSize()
    }
}

final class IntrinsicTextView: NSTextView {
    var lastRenderedContent: String?

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
}
