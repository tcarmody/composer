import SwiftUI

struct NewItemAction {
    let title: String
    let perform: () -> Void
}

struct RefreshAction {
    let perform: () -> Void
}

private struct NewItemActionKey: FocusedValueKey {
    typealias Value = NewItemAction
}

private struct RefreshActionKey: FocusedValueKey {
    typealias Value = RefreshAction
}

extension FocusedValues {
    var newItemAction: NewItemAction? {
        get { self[NewItemActionKey.self] }
        set { self[NewItemActionKey.self] = newValue }
    }
    var refreshAction: RefreshAction? {
        get { self[RefreshActionKey.self] }
        set { self[RefreshActionKey.self] = newValue }
    }
}
