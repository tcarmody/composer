import SwiftUI

// Loads that finish quickly should show nothing at all. A spinner that appears
// and vanishes inside 200ms reads as a flicker, not as progress — and when it
// replaces a whole pane, arrowing down a list strobes between content and an
// empty box. Both indicators here wait before showing anything, and the
// reload variant leaves the existing content in place while it waits.

/// How long a load runs before it's worth telling the user about.
private let indicatorDelay: Duration = .milliseconds(250)

/// Fills a pane that has nothing to keep on screen yet — a first load, or one
/// that follows an empty state. Renders nothing until the delay elapses.
struct DelayedProgressView: View {
    var delay: Duration = indicatorDelay
    @State private var isVisible = false

    var body: some View {
        Group {
            if isVisible {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading")
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            isVisible = true
        }
    }
}

extension View {
    /// Layers a small indicator over content that is already on screen while
    /// it's being replaced, instead of blanking the pane. Use with a model's
    /// reload flag, which keeps the previous value in `loaded` rather than
    /// dropping back to `loading`.
    func reloadIndicator(_ isReloading: Bool) -> some View {
        modifier(ReloadIndicator(isReloading: isReloading))
    }
}

/// This indicator floats over content rather than sitting in it, which is the
/// one thing MACUX allows glass on — the navigation layer, never the content
/// itself. Older systems get the material that reads closest to it.
private struct FloatingCapsuleBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

private struct ReloadIndicator: ViewModifier {
    let isReloading: Bool
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isVisible {
                    ProgressView()
                        .controlSize(.small)
                        .padding(Spacing.small)
                        .modifier(FloatingCapsuleBackground())
                        .padding(.top, Spacing.small)
                        .accessibilityLabel("Loading")
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isVisible)
            // Re-runs on each change, and cancels the pending sleep when a
            // fast load finishes before the delay is up.
            .task(id: isReloading) {
                guard isReloading else {
                    isVisible = false
                    return
                }
                try? await Task.sleep(for: indicatorDelay)
                guard !Task.isCancelled else { return }
                isVisible = true
            }
    }
}
