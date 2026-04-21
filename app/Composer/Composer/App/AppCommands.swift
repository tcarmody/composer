import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var appState: AppState
    @FocusedValue(\.newItemAction) private var newItemAction
    @FocusedValue(\.refreshAction) private var refreshAction

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(newItemAction?.title ?? "New") {
                newItemAction?.perform()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(newItemAction == nil)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            Button("Library") { appState.selectedTab = .library }
                .keyboardShortcut("1", modifiers: .command)
            Button("Collections") { appState.selectedTab = .collections }
                .keyboardShortcut("2", modifiers: .command)
            Button("Notes") { appState.selectedTab = .notes }
                .keyboardShortcut("3", modifiers: .command)
            Button("Drafts") { appState.selectedTab = .drafts }
                .keyboardShortcut("4", modifiers: .command)
            Button("Ask") { appState.selectedTab = .ask }
                .keyboardShortcut("5", modifiers: .command)
            Divider()
            Button("Refresh") {
                refreshAction?.perform()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(refreshAction == nil)
        }
    }
}
