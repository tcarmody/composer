import Foundation
import SwiftUI

@MainActor
final class LibraryModel: ObservableObject {
    enum ListState {
        case idle
        case loading
        case loaded(ItemListResponse)
        case error(String)
    }

    enum DetailState {
        case empty
        case loading
        case loaded(Item)
        case error(String)
    }

    enum ItemAction: Equatable {
        case refresh
        case fetchContent
        case summarize
    }

    @Published var query: String = ""
    @Published var showArchived: Bool = false
    @Published var selectedId: String?
    @Published var listState: ListState = .idle
    @Published var detailState: DetailState = .empty
    @Published var runningAction: ItemAction?
    @Published var actionError: String?

    var isRefreshing: Bool { runningAction == .refresh }
    var isFetchingContent: Bool { runningAction == .fetchContent }
    var isSummarizing: Bool { runningAction == .summarize }

    private let api: APIClient
    private var searchTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?

    init(api: APIClient) {
        self.api = api
    }

    func refreshList() {
        searchTask?.cancel()
        let q = query
        let archived = showArchived
        listState = .loading
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.api.listItems(query: q, archived: archived)
                if Task.isCancelled { return }
                self.listState = .loaded(response)
            } catch {
                if Task.isCancelled { return }
                self.listState = .error(error.localizedDescription)
            }
        }
    }

    func scheduleSearch() {
        searchTask?.cancel()
        let q = query
        let archived = showArchived
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            guard let self else { return }
            self.listState = .loading
            do {
                let response = try await self.api.listItems(query: q, archived: archived)
                if Task.isCancelled { return }
                self.listState = .loaded(response)
            } catch {
                if Task.isCancelled { return }
                self.listState = .error(error.localizedDescription)
            }
        }
    }

    func select(_ id: String?) {
        selectedId = id
        detailTask?.cancel()
        guard let id else {
            detailState = .empty
            return
        }
        detailState = .loading
        detailTask = Task { [weak self] in
            guard let self else { return }
            do {
                let item = try await self.api.getItem(id: id)
                if Task.isCancelled { return }
                self.detailState = .loaded(item)
            } catch {
                if Task.isCancelled { return }
                self.detailState = .error(error.localizedDescription)
            }
        }
    }

    func toggleArchive(_ item: Item) { toggleArchive(id: item.id, isArchived: item.isArchived) }
    func delete(_ item: Item) { delete(id: item.id) }
    func refreshFromSource(_ item: Item) { refreshFromSource(id: item.id) }
    func fetchContent(_ item: Item) { fetchContent(id: item.id) }
    func summarize(_ item: Item) { summarize(id: item.id) }

    func toggleArchive(id: String, isArchived: Bool) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await self.api.setItemArchived(id: id, archived: !isArchived)
                if self.selectedId == id {
                    self.detailState = .loaded(updated)
                }
                self.refreshList()
            } catch {
                self.actionError = error.localizedDescription
            }
        }
    }

    func delete(id: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.api.deleteItem(id: id)
                if self.selectedId == id {
                    self.selectedId = nil
                    self.detailState = .empty
                }
                self.refreshList()
            } catch {
                self.actionError = error.localizedDescription
            }
        }
    }

    func refreshFromSource(id: String) {
        runAction(.refresh, id: id) { api in
            try await api.refreshItem(id: id)
        }
    }

    func fetchContent(id: String) {
        runAction(.fetchContent, id: id) { api in
            try await api.fetchItemContent(id: id)
        }
    }

    func summarize(id: String) {
        runAction(.summarize, id: id) { api in
            try await api.summarizeItem(id: id)
        }
    }

    private func runAction(
        _ action: ItemAction,
        id: String,
        _ work: @escaping (APIClient) async throws -> Item
    ) {
        guard runningAction == nil else { return }
        runningAction = action
        actionError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { self.runningAction = nil }
            do {
                let updated = try await work(self.api)
                if self.selectedId == id {
                    self.detailState = .loaded(updated)
                }
                self.refreshList()
            } catch {
                self.actionError = error.localizedDescription
            }
        }
    }
}
