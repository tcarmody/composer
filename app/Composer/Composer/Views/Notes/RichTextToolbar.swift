import SwiftUI

struct RichTextToolbar: View {
    let onBold: () -> Void
    let onItalic: () -> Void
    let onCode: () -> Void
    let onHeading: (Int) -> Void
    let onBullet: () -> Void
    let onNumbered: () -> Void
    let onQuote: () -> Void
    let onBody: () -> Void
    let onLink: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                Button("Body") { onBody() }
                Divider()
                Button("Heading 1") { onHeading(1) }
                Button("Heading 2") { onHeading(2) }
                Button("Heading 3") { onHeading(3) }
                Divider()
                Button("Quote") { onQuote() }
            } label: {
                Label("Style", systemImage: "textformat")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Divider().frame(height: 18)

            Button(action: onBold) {
                Image(systemName: "bold")
            }
            .help("Bold · ⌘B")
            .keyboardShortcut("b", modifiers: .command)

            Button(action: onItalic) {
                Image(systemName: "italic")
            }
            .help("Italic · ⌘I")
            .keyboardShortcut("i", modifiers: .command)

            Button(action: onCode) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            }
            .help("Inline code")

            Divider().frame(height: 18)

            Button(action: onBullet) {
                Image(systemName: "list.bullet")
            }
            .help("Bullet list")

            Button(action: onNumbered) {
                Image(systemName: "list.number")
            }
            .help("Numbered list")

            Divider().frame(height: 18)

            Button(action: onLink) {
                Image(systemName: "link")
            }
            .help("Link · ⌘K")
            .keyboardShortcut("k", modifiers: .command)

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
