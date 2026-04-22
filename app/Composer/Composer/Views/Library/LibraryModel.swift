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

    @Published var query: String = ""
    @Published var showArchived: Bool = false
    @Published var selectedId: String?
    @Published var listState: ListState = .idle
    @Published var detailState: DetailState = .empty
    @Published var isRefreshing: Bool = false
    @Published var refreshError: String?

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

    func toggleArchive(_ item: Item) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await self.api.setItemArchived(id: item.id, archived: !item.isArchived)
                self.detailState = .loaded(updated)
                self.refreshList()
            } catch {
                self.detailState = .error(error.localizedDescription)
            }
        }
    }

    func delete(_ item: Item) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.api.deleteItem(id: item.id)
                self.selectedId = nil
                self.detailState = .empty
                self.refreshList()
            } catch {
                self.detailState = .error(error.localizedDescription)
            }
        }
    }

    func refreshFromSource(_ item: Item) {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { self.isRefreshing = false }
            do {
                let updated = try await self.api.refreshItem(id: item.id)
                self.detailState = .loaded(updated)
                self.refreshList()
            } catch {
                self.refreshError = error.localizedDescription
            }
        }
    }
}
