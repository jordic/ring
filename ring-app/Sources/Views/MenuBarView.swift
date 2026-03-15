import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var store: KeychainStore

    @State private var expandedProvider: String?
    @State private var route: PopoverRoute?

    private enum PopoverRoute {
        case setup(Provider)
        case scopes(Provider)
        case credentialAdd

        var title: String {
            switch self {
            case .setup(let provider):
                return "Setup \(provider.label)"
            case .scopes(let provider):
                return "\(provider.label) Scopes"
            case .credentialAdd:
                return "Add Credentials"
            }
        }
    }

    private var oauth2Statuses: [ProviderStatus] {
        store.providers.filter { $0.provider.kind == .oauth2 }
    }

    private var apiKeyStatuses: [ProviderStatus] {
        store.providers.filter { $0.provider.kind == .apiKey }
    }

    var body: some View {
        Group {
            if let route {
                detailView(route)
            } else {
                rootView
            }
        }
        .frame(width: 440, height: 620)
    }

    private var rootView: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("ring")
                        .font(.headline)
                    Spacer()
                    Button {
                        store.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Refresh from keychain")

                    Button("Quit") { NSApp.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()

                sectionHeader("OAuth2")

                ForEach(oauth2Statuses) { status in
                    providerRow(status)
                    Divider().padding(.leading, 42)
                }

                sectionHeader("API Keys")

                ForEach(apiKeyStatuses) { status in
                    providerRow(status)
                    Divider().padding(.leading, 42)
                }

                sectionHeader("Credentials", trailing: {
                    AnyView(
                        Button {
                            openCredentialAdd()
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    )
                })

                credentialsList

                Divider()
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func detailView(_ route: PopoverRoute) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    self.route = nil
                    store.refresh()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Text(route.title)
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            Group {
                switch route {
                case .setup(let provider):
                    SetupWizardView(provider: provider, embeddedInPopover: true) {
                        self.route = nil
                        store.refresh()
                    }
                case .scopes(let provider):
                    ScopesView(
                        provider: provider,
                        activeScopes: store.getEntry(provider.id)?.scopes ?? [],
                        embeddedInPopover: true
                    ) {
                        self.route = nil
                        store.refresh()
                    }
                case .credentialAdd:
                    CredentialAddView(embeddedInPopover: true) {
                        self.route = nil
                        store.refresh()
                    }
                }
            }
            .environmentObject(store)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func providerRow(_ status: ProviderStatus) -> some View {
        VStack(spacing: 0) {
            ProviderRowView(
                status: status,
                isExpanded: expandedProvider == status.id
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if expandedProvider == status.id {
                        expandedProvider = nil
                    } else {
                        expandedProvider = status.id
                        if !status.configured {
                            openSetup(status.provider)
                            expandedProvider = nil
                        }
                    }
                }
            }
            .environmentObject(store)

            if expandedProvider == status.id, status.configured {
                HStack(spacing: 8) {
                    if status.connected {
                        if status.provider.kind == .oauth2 {
                            Button("Scopes") {
                                openScopes(status)
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)

                            Button("Logout") {
                                store.clearTokens(status.provider.id)
                                store.refresh()
                                expandedProvider = nil
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .foregroundStyle(.red)
                        }
                    } else {
                        Button("Login") {
                            openSetup(status.provider)
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                    }

                    Spacer()

                    Button("Remove") {
                        store.removeAll(status.provider.id)
                        store.refresh()
                        expandedProvider = nil
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private func sectionHeader(_ title: String, trailing: (() -> AnyView)? = nil) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            trailing?()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func openSetup(_ provider: Provider) {
        route = .setup(provider)
    }

    private func openScopes(_ status: ProviderStatus) {
        route = .scopes(status.provider)
    }

    private func openCredentialAdd() {
        route = .credentialAdd
    }

    @ViewBuilder
    private var credentialsList: some View {
        let ids = (store.getString("credentials.list") ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }

        if ids.isEmpty {
            Text("No credentials saved")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            ForEach(ids, id: \.self) { id in
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle")
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Text(id)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider().padding(.leading, 42)
            }
        }
    }
}

struct CredentialAddView: View {
    var embeddedInPopover: Bool = false
    var onClose: (() -> Void)? = nil

    @EnvironmentObject private var store: KeychainStore
    @Environment(\.dismiss) private var dismiss

    private func closeWindow() {
        if embeddedInPopover {
            onClose?()
            return
        }
        dismiss()
        NSApp.keyWindow?.close()
    }

    @State private var id = ""
    @State private var username = ""
    @State private var password = ""
    @State private var totpSecret = ""

    var body: some View {
        VStack(spacing: 16) {
            if !embeddedInPopover {
                HStack {
                    Text("Add Credentials")
                        .font(.headline)
                    Spacer()
                    Button("Cancel") { closeWindow() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }

                Divider()
            }

            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("ID") {
                    TextField("e.g. mybank", text: $id)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Username") {
                    TextField("", text: $username)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Password") {
                    SecureField("", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("TOTP Secret") {
                    TextField("base32 (optional)", text: $totpSecret)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Save") {
                    guard !id.isEmpty else { return }
                    if !username.isEmpty { store.setString("\(id).username", value: username) }
                    if !password.isEmpty { store.setString("\(id).password", value: password) }
                    if !totpSecret.isEmpty { store.setString("\(id).totp_secret", value: totpSecret) }
                    updateCredentialsList(id: id)
                    store.refresh()
                    closeWindow()
                }
                .buttonStyle(.borderedProminent)
                .disabled(id.isEmpty)
            }
        }
        .padding()
        .frame(width: embeddedInPopover ? nil : 340, height: embeddedInPopover ? nil : 320)
    }

    private func updateCredentialsList(id: String) {
        var ids = (store.getString("credentials.list") ?? "")
            .split(separator: ",").map(String.init)
        if !ids.contains(id) { ids.append(id) }
        store.setString("credentials.list", value: ids.joined(separator: ","))
    }
}

extension Provider: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Provider, rhs: Provider) -> Bool { lhs.id == rhs.id }
}
