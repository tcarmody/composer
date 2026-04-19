import SwiftUI

struct HealthBadge: View {
    let status: HealthStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(tooltip)
    }

    private var dotColor: Color {
        switch status {
        case .unknown: return .gray
        case .ok: return .green
        case .unreachable: return .red
        }
    }

    private var label: String {
        switch status {
        case .unknown: return "checking…"
        case .ok(let version, _): return "ok · v\(version)"
        case .unreachable: return "backend unreachable"
        }
    }

    private var tooltip: String {
        switch status {
        case .unknown: return "Checking backend health"
        case .ok(let version, let schema):
            return "Composer backend OK · v\(version) · schema v\(schema)"
        case .unreachable(let msg):
            return "Composer backend unreachable: \(msg)"
        }
    }
}

#Preview("OK") {
    HealthBadge(status: .ok(version: "0.1.0", schemaVersion: 3))
        .padding()
}

#Preview("Unreachable") {
    HealthBadge(status: .unreachable("connection refused"))
        .padding()
}
