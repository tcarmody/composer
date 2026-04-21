import Foundation

@MainActor
final class AskModel: ObservableObject {
    enum StreamState: Equatable {
        case idle
        case streaming
        case done
        case error(String)
    }

    @Published var input: String = ""
    @Published var scope: SourceFilter = .all
    @Published var answer: String = ""
    @Published var citations: [Citation] = []
    @Published var state: StreamState = .idle
    @Published var vectorSearchUsed: Bool = false
    @Published var lastQuery: String = ""
    @Published var selectedCitationId: String?

    private let api: APIClient
    private var streamTask: Task<Void, Never>?

    init(api: APIClient) {
        self.api = api
    }

    deinit {
        streamTask?.cancel()
    }

    var isStreaming: Bool {
        if case .streaming = state { return true }
        return false
    }

    var canAsk: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    func ask() {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isStreaming else { return }

        streamTask?.cancel()
        lastQuery = query
        answer = ""
        citations = []
        vectorSearchUsed = false
        selectedCitationId = nil
        state = .streaming

        let scope = self.scope
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = self.api.streamChat(
                    query: query,
                    sourceTypes: scope.sourceTypes
                )
                for try await event in stream {
                    if Task.isCancelled { return }
                    switch event {
                    case .citations(let cites, let vecUsed):
                        self.citations = cites
                        self.vectorSearchUsed = vecUsed
                    case .delta(let text):
                        self.answer += text
                    case .done:
                        self.state = .done
                    case .error(let msg):
                        self.state = .error(msg)
                    }
                }
                if case .streaming = self.state {
                    self.state = .done
                }
            } catch is CancellationError {
                return
            } catch {
                self.state = .error(error.localizedDescription)
            }
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        if case .streaming = state {
            state = .idle
        }
    }

    func reset() {
        cancel()
        input = ""
        answer = ""
        citations = []
        lastQuery = ""
        vectorSearchUsed = false
        selectedCitationId = nil
        state = .idle
    }
}
