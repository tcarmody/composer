import AppKit
import SwiftUI

struct FactCheckPanel: View {
    @ObservedObject var model: DraftsModel
    @EnvironmentObject private var app: AppState
    var onLocate: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if case .error(let msg) = model.factCheckPhase {
                        errorBanner(msg)
                    }
                    if model.factCheckClaims.isEmpty,
                       case .done = model.factCheckPhase {
                        Text("No verifiable claims found in this passage.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                    if model.factCheckClaims.isEmpty,
                       case .extracting = model.factCheckPhase {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Looking for verifiable claims…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                    }
                    ForEach(model.factCheckClaims) { claim in
                        ClaimRow(claim: claim, onLocate: { onLocate(claim.claim) })
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 360)
        .background(app.theme.chromeBackground)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fact-check").font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                model.cancelFactCheck()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusText: String {
        switch model.factCheckPhase {
        case .idle:
            return ""
        case .extracting(let sel):
            return sel == nil ? "Reading the draft…" : "Reading the selection…"
        case .verifying:
            let pending = model.factCheckClaims.filter {
                if case .pending = $0.status { return true } else { return false }
            }.count
            return "Verifying \(pending) of \(model.factCheckClaims.count)"
        case .done:
            let n = model.factCheckClaims.count
            return "Done — \(n) claim\(n == 1 ? "" : "s")"
        case .error:
            return "Failed"
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .cornerRadius(6)
    }
}

private struct ClaimRow: View {
    let claim: FactCheckClaimState
    let onLocate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                badge
                Button(action: onLocate) {
                    Text("\u{201C}\(claim.claim)\u{201D}")
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Jump to claim in draft")
            }
            switch claim.status {
            case .pending:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Searching the web…").font(.caption).foregroundStyle(.secondary)
                }
            case .failed(let msg):
                Text(msg).font(.caption).foregroundStyle(.red)
            case .verified:
                if !claim.explanation.isEmpty {
                    Text(claim.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let correction = claim.suggestedCorrection {
                    HStack(alignment: .top, spacing: 6) {
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Suggested correction")
                                .font(.caption2.bold())
                                .foregroundStyle(.orange)
                            Text(correction).font(.caption)
                        }
                    }
                }
                if !claim.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(claim.sources.prefix(4), id: \.id) { source in
                            VStack(alignment: .leading, spacing: 2) {
                                Button {
                                    if let url = URL(string: source.url) {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Text(source.title)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.link)
                                if let snippet = source.snippet {
                                    Text(snippet)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .background(rowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var badge: some View {
        let (symbol, color) = badgeAttrs
        return Image(systemName: symbol)
            .foregroundStyle(color)
            .font(.system(size: 14))
            .frame(width: 16, height: 16)
            .padding(.top, 2)
    }

    private var badgeAttrs: (String, Color) {
        switch claim.status {
        case .pending: return ("ellipsis.circle", .secondary)
        case .failed: return ("exclamationmark.triangle.fill", .red)
        case .verified:
            switch claim.verdict {
            case .supported: return ("checkmark.circle.fill", .green)
            case .contradicted: return ("xmark.octagon.fill", .red)
            case .needsContext: return ("exclamationmark.triangle.fill", .orange)
            case .unverified, .none: return ("questionmark.circle", .secondary)
            }
        }
    }

    private var borderColor: Color {
        switch claim.status {
        case .pending: return Color.secondary.opacity(0.2)
        case .failed: return Color.red.opacity(0.4)
        case .verified:
            switch claim.verdict {
            case .supported: return Color.green.opacity(0.35)
            case .contradicted: return Color.red.opacity(0.45)
            case .needsContext: return Color.orange.opacity(0.4)
            case .unverified, .none: return Color.secondary.opacity(0.2)
            }
        }
    }

    private var rowBackground: Color {
        Color.primary.opacity(0.02)
    }
}
