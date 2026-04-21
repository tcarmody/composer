import SwiftUI

struct AskTranscriptView: View {
    @ObservedObject var model: AskModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.turns.isEmpty {
                        EmptyStateView()
                    } else {
                        ForEach(model.turns) { turn in
                            TurnView(
                                turn: turn,
                                isFocused: model.focusedTurnId == turn.id
                                    || (model.focusedTurnId == nil && turn.id == model.turns.last?.id),
                                onCitationTap: { index in
                                    model.focusTurn(turn.id)
                                    if let hit = turn.citations.first(where: { $0.index == index }) {
                                        model.selectedCitationId = hit.id
                                    }
                                }
                            )
                            .id(turn.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .onChange(of: model.turns.last?.answer) { _, _ in
                withAnimation(.linear(duration: 0.1)) {
                    if let id = model.turns.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: model.turns.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    if let id = model.turns.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Ask your archive")
                .font(.title3.weight(.medium))
            Text("Questions are answered from your articles, notes, and drafts. Every claim is grounded in a cited source.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

private struct TurnView: View {
    let turn: AskModel.Turn
    let isFocused: Bool
    let onCitationTap: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuestionBubble(text: turn.question)
            AnswerBubble(
                text: turn.answer,
                citations: turn.citations,
                state: turn.state,
                onCitationTap: onCitationTap
            )
        }
        .opacity(isFocused ? 1.0 : 0.85)
    }
}

private struct QuestionBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                .textSelection(.enabled)
        }
    }
}

private struct AnswerBubble: View {
    let text: String
    let citations: [Citation]
    let state: AskModel.StreamState
    let onCitationTap: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if text.isEmpty, case .streaming = state {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching…").foregroundStyle(.secondary).font(.callout)
                }
                .padding(.vertical, 4)
            } else {
                AnswerText(
                    text: text,
                    citationIndices: Set(citations.map(\.index)),
                    onCitationTap: onCitationTap
                )
            }

            if case .error(let message) = state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AnswerText: View {
    let text: String
    let citationIndices: Set<Int>
    let onCitationTap: (Int) -> Void

    var body: some View {
        Text(attributed)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "composer-cite",
                   let index = Int(url.lastPathComponent) {
                    onCitationTap(index)
                    return .handled
                }
                return .systemAction
            })
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        let pattern = /\[(\d+(?:\s*,\s*\d+)*)\]/
        for match in text.matches(of: pattern) {
            let range = match.range
            guard let attrRange = Range(range, in: result) else { continue }
            let groupText = String(match.output.1)
            let numbers = groupText
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard let first = numbers.first, citationIndices.contains(first) else { continue }
            result[attrRange].foregroundColor = .accentColor
            result[attrRange].font = .body.weight(.medium)
            if let url = URL(string: "composer-cite://\(first)") {
                result[attrRange].link = url
            }
        }
        return result
    }
}
