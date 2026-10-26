import SwiftUI

@main
struct ComposerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            themed(MainView())
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(appState: appState)
        }

        Settings {
            themed(SettingsView())
        }
    }

    /// Every scene gets the same state and the same appearance tokens.
    /// Settings is a sibling scene, not a child of the main window, so it
    /// inherits nothing on its own — leave it out and the theme picker sits
    /// in a window that never shows the palette it's picking.
    ///
    /// The light/dark decision is not here: `preferredColorScheme` doesn't
    /// reach a Settings-scene window, so AppState drives it through
    /// `NSApp.appearance` instead, which every window inherits.
    private func themed<Content: View>(_ content: Content) -> some View {
        content
            .environmentObject(appState)
            .composerAppearance(
                theme: appState.theme,
                typeface: appState.typeface,
                density: appState.listDensity
            )
    }
}
