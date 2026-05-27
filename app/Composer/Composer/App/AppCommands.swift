import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var appState: AppState
    @FocusedValue(\.newItemAction) private var newItemAction
    @FocusedValue(\.refreshAction) private var refreshAction
    @FocusedValue(\.saveAction) private var saveAction
    @FocusedValue(\.deleteAction) private var deleteAction
    @FocusedValue(\.archiveAction) private var archiveAction
    @FocusedValue(\.formatAction) private var formatAction
    @FocusedValue(\.toolsAction) private var toolsAction
    @FocusedValue(\.shareAction) private var shareAction

    var body: some Commands {
        // MARK: File

        CommandGroup(replacing: .newItem) {
            Button(newItemAction?.title ?? "New") {
                newItemAction?.perform()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(newItemAction == nil)
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button("Save") { saveAction?.perform() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(saveAction == nil || !(saveAction?.isEnabled ?? false))
        }

        // MARK: View — top-level mode switches and panel toggles

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
            Divider()
            Button(appState.isDraftPanelVisible ? "Hide Draft Panel" : "Show Draft Panel") {
                appState.toggleDraftPanel()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            .disabled(appState.selectedTab == .drafts)
        }

        // MARK: Edit — Archive / Delete focus-aware

        CommandGroup(after: .pasteboard) {
            Divider()
            if let archive = archiveAction {
                Button(archive.title, action: archive.perform)
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            if let del = deleteAction {
                Button(del.title, role: .destructive, action: del.perform)
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(!del.isEnabled)
            }
        }

        // MARK: Format — Smart quotes (focus-aware)

        CommandMenu("Format") {
            Button("Convert Straight Quotes to Smart Quotes in Selection") {
                formatAction?.smartQuotes(.selection)
            }
            .disabled(formatAction == nil || !(formatAction?.hasSelection ?? false))
            Button("Convert Straight Quotes to Smart Quotes in Document") {
                formatAction?.smartQuotes(.all)
            }
            .disabled(formatAction == nil)
        }

        // MARK: Tools — Assist + Fact-check (focus-aware to draft editor)

        CommandMenu("Tools") {
            Section("AI Assist") {
                ForEach(DraftAssistAction.allCases, id: \.self) { action in
                    Button(action.label) {
                        toolsAction?.runAssist(action)
                    }
                    .disabled(toolsAction == nil)
                }
            }
            Section("Fact-check") {
                Button("Fact-check Selection") {
                    toolsAction?.runFactCheck(.selection)
                }
                .disabled(toolsAction == nil || !(toolsAction?.hasSelection ?? false))
                Button("Fact-check Entire Draft") {
                    toolsAction?.runFactCheck(.all)
                }
                .disabled(toolsAction == nil)
            }
        }

        // MARK: Share — Export drafts

        CommandGroup(after: .saveItem) {
            if let share = shareAction {
                Divider()
                Section("Export") {
                    Button("Export as Markdown…") { share.export(.markdown) }
                    Button("Export as HTML…") { share.export(.html) }
                    Button("Copy HTML to Clipboard") { share.export(.copyHTML) }
                }
            }
        }
    }
}
