import AppKit
import SwiftUI

// Appearance tokens reach every surface through the environment instead of
// each view reaching into AppState for `app.theme` / `app.typeface`. MainView
// installs them once at the root; everything below inherits. That's the fix
// for palettes and typefaces that used to land on the reading panes only,
// leaving the lists, Ask, and Collections on system defaults.

// MARK: - Environment plumbing

private struct ComposerThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .auto
}

private struct ComposerTypefaceKey: EnvironmentKey {
    static let defaultValue: AppTypeface = .system
}

private struct ComposerDensityKey: EnvironmentKey {
    static let defaultValue: ListDensity = .comfortable
}

extension EnvironmentValues {
    var composerTheme: AppTheme {
        get { self[ComposerThemeKey.self] }
        set { self[ComposerThemeKey.self] = newValue }
    }

    var composerTypeface: AppTypeface {
        get { self[ComposerTypefaceKey.self] }
        set { self[ComposerTypefaceKey.self] = newValue }
    }

    var composerDensity: ListDensity {
        get { self[ComposerDensityKey.self] }
        set { self[ComposerDensityKey.self] = newValue }
    }
}

extension View {
    /// Installs the palette, typeface, and list density for everything below.
    /// Call this once, at the window root.
    func composerAppearance(
        theme: AppTheme,
        typeface: AppTypeface,
        density: ListDensity
    ) -> some View {
        self
            .environment(\.composerTheme, theme)
            .environment(\.composerTypeface, typeface)
            .environment(\.composerDensity, density)
            .tint(theme.accentColor)
    }
}

// MARK: - Surfaces

/// What a surface is for. Decides how much of the palette it takes on — a
/// list has to keep system selection and label colors working, an article
/// body doesn't.
enum ComposerSurfaceRole {
    /// Article bodies and editor canvases. Opaque by design.
    case reading
    /// Lists, sidebars, transient panels.
    case list
    /// Title bars and formatting toolbars, which read as chrome rather than body.
    case chrome
}

extension View {
    /// Paints a surface in the current palette.
    func composerSurface(_ role: ComposerSurfaceRole) -> some View {
        modifier(ComposerSurface(role: role))
    }
}

private struct ComposerSurface: ViewModifier {
    @Environment(\.composerTheme) private var theme
    let role: ComposerSurfaceRole

    func body(content: Content) -> some View {
        let fill = theme.fill(for: role)
        // A List paints its own backdrop, so the palette only shows through
        // once that's out of the way — but only bother when we actually have
        // a fill, or Auto would leave the list transparent over the window.
        return content
            .modifier(ComposerScrollBackground(hidden: role == .list && fill != nil))
            .background {
                if let fill { fill }
            }
            .modifier(ComposerForeground(theme: theme, role: role))
    }
}

private struct ComposerScrollBackground: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        if hidden {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

/// Reading and chrome surfaces pin their own ink. Lists deliberately don't —
/// forcing a foreground style on rows fights List's selection highlight, so
/// they rely on `AppTheme.colorScheme` flipping the system label colors.
private struct ComposerForeground: ViewModifier {
    let theme: AppTheme
    let role: ComposerSurfaceRole

    func body(content: Content) -> some View {
        switch role {
        case .reading, .chrome:
            content.foregroundStyle(theme.textColor, theme.secondaryTextColor)
        case .list:
            content
        }
    }
}

extension AppTheme {
    /// `nil` means "paint nothing" — let the window material show through.
    /// Auto defers on lists and panels so sidebar vibrancy survives.
    func fill(for role: ComposerSurfaceRole) -> Color? {
        switch role {
        case .reading:
            // macOS 26 renders its own material behind window content and
            // floats the toolbar over it. An opaque paint on the root blocks
            // that, so Auto — the theme with no opinion of its own — steps out
            // of the way. Named palettes still paint: opting out of the system
            // appearance is the entire point of picking one.
            if self == .auto, #available(macOS 26, *) { return nil }
            return backgroundColor
        case .list:
            return self == .auto ? nil : backgroundColor
        case .chrome:
            return chromeBackground
        }
    }

    /// Dark palettes have to switch the whole control stack, not just the
    /// backgrounds we paint — otherwise system label, selection, and control
    /// colors resolve against the wrong appearance and lists go unreadable.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .manuscript, .forest, .ocean: return .light
        case .noir, .ember, .midnight: return .dark
        }
    }

    /// Applied to `NSApp` rather than through `preferredColorScheme`, because
    /// a scene modifier only reaches its own scene: Settings, panels, and
    /// anything else the app opens would keep the system appearance and clash
    /// with a themed main window. `nil` hands control back to the system.
    var appKitAppearance: NSAppearance? {
        switch colorScheme {
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        case .none: return nil
        @unknown default: return nil
        }
    }
}

// MARK: - Spacing

/// A 4pt spacing grid. The app had fourteen distinct padding values, most of
/// them within two points of each other, which reads as drift rather than
/// intent. Reach for a step here instead of a literal.
///
/// `tight` is the one deliberate half-step: control interiors — badge and
/// capsule padding — where 4pt is visibly too much. `0` stays a literal,
/// because it means "no gap", not "the smallest gap".
enum Spacing {
    static let tight: CGFloat = 2
    static let xsmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xlarge: CGFloat = 20
    static let xxlarge: CGFloat = 24
    static let xxxlarge: CGFloat = 32
}

// MARK: - Status tones

/// Semantic tones for badges, verdicts, and error banners. Views ask for a
/// tone rather than naming a color, because the wash behind one has to be
/// tuned per appearance: an 18% green that reads as a soft tint on white all
/// but disappears against a dark palette like Noir or Midnight.
///
/// Reads `\.colorScheme`, which the theme drives via `AppTheme.colorScheme`,
/// so a dark palette gets the dark treatment even under a light system.
enum StatusTone {
    case positive
    case caution
    case negative
    case neutral

    /// Full-strength color for glyphs and text.
    var accent: Color {
        switch self {
        case .positive: return .green
        case .caution: return .orange
        case .negative: return .red
        case .neutral: return .secondary
        }
    }

    /// Background wash behind a badge or banner.
    func fill(_ scheme: ColorScheme) -> Color {
        accent.opacity(scheme == .dark ? 0.30 : 0.18)
    }

    /// Hairline around a card or row.
    func border(_ scheme: ColorScheme) -> Color {
        accent.opacity(scheme == .dark ? 0.55 : 0.38)
    }
}

// MARK: - Type roles

extension AppTypeface {
    /// The title line of a row in Library, Notes, Drafts, and Collections.
    var rowTitle: Font { font(size: 13).weight(.medium) }

    /// Body copy in article and transcript views.
    var readingBody: Font { font(size: 14) }
}
