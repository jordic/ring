import SwiftUI

struct ScopesView: View {
    let provider: Provider
    let activeScopes: [String]
    var embeddedInPopover: Bool = false
    var onDone: (() -> Void)? = nil

    @EnvironmentObject private var store: KeychainStore
    @Environment(\.dismiss) private var dismiss
    private func closeWindow() {
        if embeddedInPopover {
            onDone?()
            return
        }
        dismiss()
        NSApp.keyWindow?.close()
    }

    @State private var currentScopes: Set<String> = []
    @State private var selectedScopes: Set<String> = []
    @State private var isAuthorizing = false
    @State private var errorMessage: String?

    private let oauth = OAuthFlow()

    private var scopeStatuses: [ScopeStatus] {
        provider.scopeStatuses(activeScopes: Array(currentScopes))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !embeddedInPopover {
                HStack {
                    Text("\(provider.label) Scopes")
                        .font(.headline)
                    Spacer()
                    Button("Done") { closeWindow() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding()

                Divider()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            if provider.useDeviceFlow {
                Text("This provider uses Device Flow. Scope re-authorization is only supported from the CLI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            List {
                ForEach(scopeStatuses) { scopeStatus in
                    HStack(spacing: 12) {
                        if scopeStatus.isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(scopeStatus.label)
                                    .font(.body)
                                Text(scopeStatus.definition.id)
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                                if scopeStatus.definition.description.isEmpty == false {
                                    Text(scopeStatus.definition.description)
                                        .font(.caption)
                                        .foregroundStyle(Color.secondary.opacity(0.6))
                                }
                            }

                            Spacer()

                            Text("Granted")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Toggle(isOn: binding(for: scopeStatus.definition)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scopeStatus.label)
                                        .font(.body)
                                    Text(scopeStatus.definition.id)
                                        .font(.caption)
                                        .foregroundStyle(Color.secondary)
                                    if scopeStatus.definition.description.isEmpty == false {
                                        Text(scopeStatus.definition.description)
                                            .font(.caption)
                                            .foregroundStyle(Color.secondary.opacity(0.6))
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                            .disabled(isAuthorizing || provider.useDeviceFlow)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)

            Divider()

            HStack {
                Text("\(selectedScopes.count) scope\(selectedScopes.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(isAuthorizing ? "Authorizing…" : "Authorize Selected") {
                    Task { await authorizeSelectedScopes() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedScopes.isEmpty || isAuthorizing || provider.useDeviceFlow)
            }
            .padding()
        }
        .frame(width: embeddedInPopover ? nil : 420, height: embeddedInPopover ? nil : 460)
        .onAppear {
            currentScopes = Set(activeScopes)
        }
    }

    private func binding(for scopeDefinition: ScopeDefinition) -> Binding<Bool> {
        let scope = normalizedScope(from: scopeDefinition)
        return Binding(
            get: { selectedScopes.contains(scope) },
            set: { isOn in
                if isOn {
                    selectedScopes.insert(scope)
                } else {
                    selectedScopes.remove(scope)
                }
            }
        )
    }

    private func normalizedScope(from definition: ScopeDefinition) -> String {
        definition.oauthScope.isEmpty ? definition.id : definition.oauthScope
    }

    private func authorizeSelectedScopes() async {
        isAuthorizing = true
        errorMessage = nil
        defer { isAuthorizing = false }

        guard let clientID = store.getClientID(provider.id) else {
            errorMessage = "Not configured — run: ring setup \(provider.id)"
            return
        }
        let clientSecret = store.getClientSecret(provider.id) ?? ""

        do {
            let entry = try await oauth.addScopes(
                provider: provider,
                clientID: clientID,
                clientSecret: clientSecret,
                currentScopes: Array(currentScopes),
                newScopes: Array(selectedScopes)
            )

            store.setEntry(provider.id, entry: entry)
            store.refresh()
            currentScopes = Set(entry.scopes)
            selectedScopes.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
