import Foundation

@MainActor
final class AskModel: ObservableObject {
    enum StreamState: Equatable {
        case idle
        case streaming
        case done
        case error(String)
    }

    struct Turn: Identifiable, Equatable {
        let id: UUID
        var question: String
        var answer: String
        var citations: [Citation]
        var vectorSearchUsed: Bool
        var state: StreamState
    }

    @Published var input: String = ""
    @Published var scope: SourceFilter = .all
    @Published var turns: [Turn] = []
    @Published var selectedCitationId: String?
    @Published var focusedTurnId: UUID?

    private let api: APIClient
    private var streamTask: Task<Void, Never>?

    init(api: APIClient) {
        self.api = api
    }

    deinit {
        streamTask?.cancel()
    }

    private var focusedTurn: Turn? {
        if let id = focusedTurnId, let t = turns.first(where: { $0.id == id }) {
            return t
        }
        return turns.last
    }

    var citations: [Citation] { focusedTurn?.citations ?? [] }
    var vectorSearchUsed: Bool { focusedTurn?.vectorSearchUsed ?? false }
    var currentState: StreamState { focusedTurn?.state ?? .idle }

    var isStreaming: Bool {
        guard let last = turns.last else { return false }
        if case .streaming = last.state { return true }
        return false
    }

    var canAsk: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    func ask() {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isStreaming else { return }

        streamTask?.cancel()

        let history: [(role: String, content: String)] = turns.flatMap { t -> [(String, String)] in
            guard case .done = t.state, !t.answer.isEmpty else { return [] }
            return [("user", t.question), ("assistant", t.answer)]
        }

        let turn = Turn(
            id: UUID(),
            question: query,
            answer: "",
            citations: [],
            vectorSearchUsed: false,
            state: .streaming
        )
        turns.append(turn)
        input = ""
        selectedCitationId = nil
        focusedTurnId = nil

        let turnId = turn.id
        let scope = self.scope
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = self.api.streamChat(
                    query: query,
                    sourceTypes: scope.sourceTypes,
                    history: history
                )
                for try await event in stream {
                    if Task.isCancelled { return }
                    guard let idx = self.turns.firstIndex(where: { $0.id == turnId }) else { return }
                    switch event {
                    case .citations(let cites, let vecUsed):
                        self.turns[idx].citations = cites
                        self.turns[idx].vectorSearchUsed = vecUsed
                    case .delta(let text):
                        self.turns[idx].answer += text
                    case .done:
                        self.turns[idx].state = .done
                    case .error(let msg):
                        self.turns[idx].state = .error(msg)
                    }
                }
                if let idx = self.turns.firstIndex(where: { $0.id == turnId }),
                   case .streaming = self.turns[idx].state {
                    self.turns[idx].state = .done
                }
            } catch is CancellationError {
                return
            } catch {
                if let idx = self.turns.firstIndex(where: { $0.id == turnId }) {
                    self.turns[idx].state = .error(error.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        if let idx = turns.indices.last,
           case .streaming = turns[idx].state {
            turns[idx].state = .done
        }
    }

    func reset() {
        cancel()
        input = ""
        turns = []
        selectedCitationId = nil
        focusedTurnId = nil
    }

    func focusTurn(_ id: UUID) {
        focusedTurnId = id
    }
}
