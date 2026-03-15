import SwiftUI

struct ProviderRowView: View {
    let status: ProviderStatus
    let isExpanded: Bool
    let onTap: () -> Void

    @EnvironmentObject private var store: KeychainStore

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Image(systemName: status.provider.sfSymbol)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)

                    Text(status.provider.label)
                        .font(.body)

                    Spacer()

                    statusBadge
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded detail
            if isExpanded {
                expandedView
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Status badge

    @ViewBuilder
    private var statusBadge: some View {
        if !status.configured {
            Text("Setup")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        } else {
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)
        }
    }

    private var statusDotColor: Color {
        switch status.statusColor {
        case .green:  return .green
        case .yellow: return .yellow
        case .grey:   return Color.secondary.opacity(0.5)
        }
    }

    // MARK: - Expanded content

    @ViewBuilder
    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.bottom, 2)

            if status.connected, let entry = status.entry {
                // Active scopes
                if !entry.scopes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scopes (\(entry.scopes.count)):")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(Array(entry.scopes.prefix(4)), id: \.self) { scope in
                            Text("• \(scope)")
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        if entry.scopes.count > 4 {
                            Text("+\(entry.scopes.count - 4) more")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Expiry
                if let expiresAt = entry.expiresAt {
                    HStack {
                        Text("Expires:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(expiresAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(status.needsRefresh ? .orange : .secondary)
                    }
                }
            }

            // Status line
            HStack {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 6, height: 6)
                Text(statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusDescription: String {
        if !status.configured   { return "Not configured — tap to set up" }
        if !status.connected    { return "Not logged in" }
        if status.needsRefresh  { return "Token needs refresh" }
        return "Connected"
    }
}
