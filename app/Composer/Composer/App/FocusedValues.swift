import SwiftUI

struct NewItemAction {
    let title: String
    let perform: () -> Void
}

struct RefreshAction {
    let perform: () -> Void
}

struct SaveAction {
    let isEnabled: Bool
    let perform: () -> Void
}

struct DeleteAction {
    let title: String
    let isEnabled: Bool
    let perform: () -> Void
}

enum SmartQuotesScope { case selection, all }

struct FormatAction {
    let smartQuotes: (SmartQuotesScope) -> Void
    let hasSelection: Bool
}

enum FactCheckScope { case selection, all }

struct ToolsAction {
    let runAssist: (DraftAssistAction) -> Void
    let runFactCheck: (FactCheckScope) -> Void
    let hasSelection: Bool
}

enum ExportFormat { case markdown, html, copyHTML }

struct ShareAction {
    let export: (ExportFormat) -> Void
}

struct ArchiveAction {
    let title: String
    let perform: () -> Void
}

private struct NewItemActionKey: FocusedValueKey { typealias Value = NewItemAction }
private struct RefreshActionKey: FocusedValueKey { typealias Value = RefreshAction }
private struct SaveActionKey: FocusedValueKey { typealias Value = SaveAction }
private struct DeleteActionKey: FocusedValueKey { typealias Value = DeleteAction }
private struct FormatActionKey: FocusedValueKey { typealias Value = FormatAction }
private struct ToolsActionKey: FocusedValueKey { typealias Value = ToolsAction }
private struct ShareActionKey: FocusedValueKey { typealias Value = ShareAction }
private struct ArchiveActionKey: FocusedValueKey { typealias Value = ArchiveAction }

extension FocusedValues {
    var newItemAction: NewItemAction? {
        get { self[NewItemActionKey.self] }
        set { self[NewItemActionKey.self] = newValue }
    }
    var refreshAction: RefreshAction? {
        get { self[RefreshActionKey.self] }
        set { self[RefreshActionKey.self] = newValue }
    }
    var saveAction: SaveAction? {
        get { self[SaveActionKey.self] }
        set { self[SaveActionKey.self] = newValue }
    }
    var deleteAction: DeleteAction? {
        get { self[DeleteActionKey.self] }
        set { self[DeleteActionKey.self] = newValue }
    }
    var formatAction: FormatAction? {
        get { self[FormatActionKey.self] }
        set { self[FormatActionKey.self] = newValue }
    }
    var toolsAction: ToolsAction? {
        get { self[ToolsActionKey.self] }
        set { self[ToolsActionKey.self] = newValue }
    }
    var shareAction: ShareAction? {
        get { self[ShareActionKey.self] }
        set { self[ShareActionKey.self] = newValue }
    }
    var archiveAction: ArchiveAction? {
        get { self[ArchiveActionKey.self] }
        set { self[ArchiveActionKey.self] = newValue }
    }
}
