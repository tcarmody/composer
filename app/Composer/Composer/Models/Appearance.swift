import AppKit
import SwiftUI

enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case manuscript
    case noir
    case ember
    case forest
    case ocean
    case midnight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .manuscript: return "Manuscript"
        case .noir: return "Noir"
        case .ember: return "Ember"
        case .forest: return "Forest"
        case .ocean: return "Ocean"
        case .midnight: return "Midnight"
        }
    }

    var description: String {
        switch self {
        case .auto: return "Follows system appearance"
        case .manuscript: return "Warm cream with rich brown ink"
        case .noir: return "High contrast black and white"
        case .ember: return "Deep charcoal with warm orange accents"
        case .forest: return "Soft sage with deep green tones"
        case .ocean: return "Cool slate with teal highlights"
        case .midnight: return "Deep navy with golden accents"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .auto: return Color(NSColor.textBackgroundColor)
        case .manuscript: return Color(red: 0.973, green: 0.957, blue: 0.914)
        case .noir: return .black
        case .ember: return Color(red: 0.110, green: 0.098, blue: 0.090)
        case .forest: return Color(red: 0.941, green: 0.957, blue: 0.945)
        case .ocean: return Color(red: 0.957, green: 0.969, blue: 0.980)
        case .midnight: return Color(red: 0.047, green: 0.071, blue: 0.133)
        }
    }

    var textColor: Color {
        switch self {
        case .auto: return Color(NSColor.textColor)
        case .manuscript: return Color(red: 0.173, green: 0.141, blue: 0.086)
        case .noir: return .white
        case .ember: return Color(red: 0.980, green: 0.961, blue: 0.941)
        case .forest: return Color(red: 0.102, green: 0.180, blue: 0.102)
        case .ocean: return Color(red: 0.059, green: 0.090, blue: 0.165)
        case .midnight: return Color(red: 0.886, green: 0.910, blue: 0.941)
        }
    }

    var secondaryTextColor: Color {
        switch self {
        case .auto: return Color(NSColor.secondaryLabelColor)
        case .manuscript: return Color(red: 0.361, green: 0.314, blue: 0.251)
        case .noir: return Color(red: 0.533, green: 0.533, blue: 0.533)
        case .ember: return Color(red: 0.659, green: 0.635, blue: 0.620)
        case .forest: return Color(red: 0.290, green: 0.373, blue: 0.290)
        case .ocean: return Color(red: 0.278, green: 0.333, blue: 0.416)
        case .midnight: return Color(red: 0.580, green: 0.639, blue: 0.722)
        }
    }

    var accentColor: Color {
        switch self {
        case .auto: return .accentColor
        case .manuscript: return Color(red: 0.545, green: 0.251, blue: 0.0)
        case .noir: return .white
        case .ember: return Color(red: 0.976, green: 0.451, blue: 0.086)
        case .forest: return Color(red: 0.176, green: 0.416, blue: 0.310)
        case .ocean: return Color(red: 0.031, green: 0.569, blue: 0.698)
        case .midnight: return Color(red: 0.984, green: 0.749, blue: 0.141)
        }
    }
}

enum ListDensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact
    case comfortable
    case spacious

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: return "Compact"
        case .comfortable: return "Comfortable"
        case .spacious: return "Spacious"
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact: return 4
        case .comfortable: return 8
        case .spacious: return 12
        }
    }

    var showSummaryPreview: Bool {
        switch self {
        case .compact: return false
        case .comfortable, .spacious: return true
        }
    }
}

enum AppTypeface: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case newYork
    case helveticaNeue
    case avenir
    case avenirNext
    case optima
    case georgia
    case palatino
    case charter
    case iowan
    case baskerville
    case didot
    case americanTypewriter
    case sfMono

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System (San Francisco)"
        case .newYork: return "New York"
        case .helveticaNeue: return "Helvetica Neue"
        case .avenir: return "Avenir"
        case .avenirNext: return "Avenir Next"
        case .optima: return "Optima"
        case .georgia: return "Georgia"
        case .palatino: return "Palatino"
        case .charter: return "Charter"
        case .iowan: return "Iowan Old Style"
        case .baskerville: return "Baskerville"
        case .didot: return "Didot"
        case .americanTypewriter: return "American Typewriter"
        case .sfMono: return "SF Mono"
        }
    }

    var fontDesign: Font.Design? {
        switch self {
        case .system: return .default
        case .newYork: return .serif
        case .sfMono: return .monospaced
        default: return nil
        }
    }

    var fontFamily: String? {
        switch self {
        case .system, .newYork, .sfMono: return nil
        case .helveticaNeue: return "Helvetica Neue"
        case .avenir: return "Avenir"
        case .avenirNext: return "Avenir Next"
        case .optima: return "Optima"
        case .georgia: return "Georgia"
        case .palatino: return "Palatino"
        case .charter: return "Charter"
        case .iowan: return "Iowan Old Style"
        case .baskerville: return "Baskerville"
        case .didot: return "Didot"
        case .americanTypewriter: return "American Typewriter"
        }
    }

    func font(size: CGFloat) -> Font {
        if let family = fontFamily {
            return .custom(family, size: size)
        }
        if let design = fontDesign {
            return .system(size: size, design: design)
        }
        return .system(size: size)
    }

    func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        switch self {
        case .system:
            return .systemFont(ofSize: size, weight: weight)
        case .sfMono:
            return .monospacedSystemFont(ofSize: size, weight: weight)
        case .newYork:
            return Self.resolve(family: "New York", size: size, weight: weight)
        default:
            if let family = fontFamily {
                return Self.resolve(family: family, size: size, weight: weight)
            }
            return .systemFont(ofSize: size, weight: weight)
        }
    }

    private static func resolve(family: String, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
        let base = NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: weight)
        if weight.rawValue >= NSFont.Weight.semibold.rawValue {
            return NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        }
        return base
    }
}

enum AppearanceDefaults {
    static func loadTheme() -> AppTheme {
        if let raw = UserDefaults.standard.string(forKey: "appTheme"),
           let t = AppTheme(rawValue: raw) {
            return t
        }
        return .auto
    }

    static func loadDensity() -> ListDensity {
        if let raw = UserDefaults.standard.string(forKey: "listDensity"),
           let d = ListDensity(rawValue: raw) {
            return d
        }
        return .comfortable
    }

    static func loadTypeface() -> AppTypeface {
        if let raw = UserDefaults.standard.string(forKey: "appTypeface"),
           let f = AppTypeface(rawValue: raw) {
            return f
        }
        return .system
    }
}
