import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var health: HealthStatus = .unknown
    @Published var selectedTab: NavTab = .library
    @Published var apiKey: String = KeychainService.shared.apiKey ?? ""
    @Published var pendingDraftSelection: String?
    @Published var pendingItemSelection: String?
    @Published var pendingNoteSelection: String?
    @Published var backendStale: Bool = false
    @Published var isDraftPanelVisible: Bool = UserDefaults.standard.bool(forKey: "isDraftPanelVisible") {
        didSet { UserDefaults.standard.set(isDraftPanelVisible, forKey: "isDraftPanelVisible") }
    }

    let api = APIClient()
    let supervisor = BackendSupervisor()
    let draftsModel: DraftsModel

    private var healthPollTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var expectedCommit: String?

    init() {
        self.draftsModel = DraftsModel(api: api)
        api.apiKey = apiKey.isEmpty ? nil : apiKey
        supervisor.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        Task { [weak self] in
            await self?.supervisor.start()
            await self?.refreshHealth()
        }
        startHealthPolling()
    }

    func setAPIKey(_ key: String) {
        apiKey = key
        api.apiKey = key.isEmpty ? nil : key
        KeychainService.shared.apiKey = key.isEmpty ? nil : key
    }

    func openDraft(id: String) {
        pendingDraftSelection = id
        selectedTab = .drafts
    }

    func openItem(id: String) {
        pendingItemSelection = id
        selectedTab = .library
    }

    func openNote(id: String) {
        pendingNoteSelection = id
        selectedTab = .notes
    }

    func quoteAs(kind: QuoteKind, selection: String, source: QuoteSource) {
        let body = QuotePrefill.build(selection: selection, source: source)
        Task { [weak self] in
            guard let self else { return }
            do {
                switch kind {
                case .note:
                    let note = try await self.api.createNote(body: body)
                    self.openNote(id: note.id)
                case .draft:
                    let draft = try await self.api.createDraft(body: body)
                    self.loadDraftInPanel(id: draft.id)
                }
            } catch {
                print("quoteAs failed: \(error)")
            }
        }
    }

    func loadDraftInPanel(id: String) {
        isDraftPanelVisible = true
        draftsModel.refreshList()
        draftsModel.select(id)
    }

    func toggleDraftPanel() {
        isDraftPanelVisible.toggle()
    }

    func startHealthPolling() {
        healthPollTask?.cancel()
        healthPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshHealth()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func refreshHealth() async {
        do {
            let resp = try await api.health()
            health = .ok(version: resp.version, schemaVersion: resp.schemaVersion)
            await checkStale(against: resp.commit)
        } catch {
            health = .unreachable(error.localizedDescription)
        }
    }

    private func checkStale(against backendCommit: String?) async {
        if expectedCommit == nil {
            expectedCommit = await readLocalCommit(repo: supervisor.projectRootPath)
        }
        guard let expected = expectedCommit, !expected.isEmpty,
              let actual = backendCommit, !actual.isEmpty,
              actual != "unknown" else {
            backendStale = false
            return
        }
        backendStale = (expected != actual)
    }
}

private func readLocalCommit(repo: String) async -> String? {
    await Task.detached {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", repo, "rev-parse", "--short", "HEAD"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }.value
}

enum HealthStatus: Equatable {
    case unknown
    case ok(version: String, schemaVersion: Int)
    case unreachable(String)
}

enum NavTab: String, CaseIterable, Identifiable {
    case library = "Library"
    case collections = "Collections"
    case notes = "Notes"
    case drafts = "Drafts"
    case ask = "Ask"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .library: return "tray.full"
        case .collections: return "rectangle.stack"
        case .notes: return "note.text"
        case .drafts: return "doc.text"
        case .ask: return "sparkle.magnifyingglass"
        }
    }
}
