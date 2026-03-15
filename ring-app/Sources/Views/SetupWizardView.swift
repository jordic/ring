import SwiftUI

struct SetupWizardView: View {
    let provider: Provider
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

    @State private var step = 1
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var apiKey = ""
    @State private var errorMessage: String?
    @State private var copiedRedirect = false
    @State private var credentialsSaved = false

    // Step 4: scopes + connect
    @State private var selectedScopes: Set<String> = []
    @State private var isConnecting = false

    private let oauth = OAuthFlow()

    private var totalSteps: Int {
        switch provider.kind {
        case .apiKey: return 2
        case .oauth2 where provider.useDeviceFlow: return 3
        case .oauth2: return 4   // dashboard → redirect → credentials → scopes
        default: return 3
        }
    }

    // Mida dinàmica: pas 4 (scopes) necessita més espai
    private var windowSize: (width: CGFloat, height: CGFloat) {
        if step == 4 { return (520, 580) }
        return (440, 380)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !embeddedInPopover {
                // Header
                HStack {
                    Image(systemName: provider.sfSymbol)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Setup \(provider.label)")
                        .font(.headline)
                    Spacer()
                    Button("Cancel") { closeWindow() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding()

                Divider()
            }

            // Step indicator
            HStack(spacing: 4) {
                ForEach(1...totalSteps, id: \.self) { n in
                    Circle()
                        .fill(n == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 12)

            // Content
            Group {
                switch step {
                case 1: step1DashboardView
                case 2 where provider.kind == .apiKey: stepAPIKeyView
                case 2: step2RedirectView
                case 3 where provider.kind == .oauth2: step3CredentialsView
                case 4: step4ScopesView
                default: EmptyView()
                }
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            // Footer
            HStack {
                if step > 1 {
                    Button("Back") {
                        errorMessage = nil
                        step -= 1
                    }
                    .buttonStyle(.plain)
                }
                Spacer()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .frame(maxWidth: 250, alignment: .trailing)
                }

                footerButton
            }
            .padding()
        }
        .frame(
            width: embeddedInPopover ? nil : windowSize.width,
            height: embeddedInPopover ? nil : windowSize.height
        )
        .animation(.easeInOut(duration: 0.2), value: step)
        .onAppear {
            clientID = store.getClientID(provider.id) ?? ""
            clientSecret = store.getClientSecret(provider.id) ?? ""
            if !clientID.isEmpty {
                credentialsSaved = true
                // Si ja tenim credencials, saltem al pas de scopes
                step = provider.kind == .apiKey ? 2 : (provider.useDeviceFlow ? 3 : 4)
            }
            // Pre-seleccionar default scopes
            for s in provider.defaultScopes {
                selectedScopes.insert(s)
            }
            if let entry = store.getEntry(provider.id) {
                for s in entry.scopes { selectedScopes.insert(s) }
            }
        }
    }

    // MARK: - Footer button

    @ViewBuilder
    private var footerButton: some View {
        switch step {
        case _ where step < totalSteps && !(step == 3 && !credentialsSaved && provider.kind == .oauth2):
            Button("Next") { step += 1 }
                .buttonStyle(.borderedProminent)

        case 2 where provider.kind == .apiKey:
            Button("Save") { saveAPIKey() }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.isEmpty)

        case 3 where provider.kind == .oauth2 && !credentialsSaved:
            Button("Save & Continue") {
                saveCredentials()
                step = 4
            }
            .buttonStyle(.borderedProminent)
            .disabled(clientID.isEmpty)

        case 3 where provider.useDeviceFlow:
            Button("Done") { closeWindow() }
                .buttonStyle(.borderedProminent)

        case 4:
            Button(isConnecting ? "Waiting for browser…" : "Authorize in Browser") {
                Task { await connect() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isConnecting)

        default:
            Button("Next") { step += 1 }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Step 1 — Dashboard

    private var step1DashboardView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create an app on the provider's dashboard")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(Array(provider.setup.steps.enumerated()), id: \.offset) { index, s in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    Text(s)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }

            Spacer()

            if !provider.setup.dashboardURL.isEmpty {
                Button {
                    if let url = URL(string: provider.setup.dashboardURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open \(provider.label) Dashboard", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Step 2 — Redirect URI

    private var redirectURI: String {
        provider.usesLocalhostCallback ? LocalCallbackServer.callbackURL : OAuthFlow.callbackURL
    }

    private var step2RedirectView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add the redirect URI to your app")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("When prompted for a redirect URI / callback URL, use:")
                .font(.callout)

            HStack {
                Text(redirectURI)
                    .font(.system(.callout, design: .monospaced))
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(redirectURI, forType: .string)
                    copiedRedirect = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedRedirect = false
                    }
                } label: {
                    Image(systemName: copiedRedirect ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(copiedRedirect ? Color.green : Color.secondary)
            }
        }
    }

    // MARK: Step 2 (API Key)

    private var stepAPIKeyView: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent(provider.setup.keyLabel) {
                SecureField("", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    // MARK: Step 3 — OAuth2 credentials

    private var step3CredentialsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Client ID") {
                TextField("", text: $clientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(credentialsSaved)
            }

            if provider.setup.needsSecret {
                LabeledContent("Client Secret") {
                    SecureField("", text: $clientSecret)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(credentialsSaved)
                }
            }

            if credentialsSaved {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    Text("Credentials saved")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit") { credentialsSaved = false }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }

                if provider.useDeviceFlow {
                    Text("GitHub uses Device Flow. Use the CLI:\n  ring login github")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Step 4 — Scopes + Connect

    private var groupedScopes: [(category: String, scopes: [ScopeDefinition])] {
        let categorized = Dictionary(grouping: provider.availableScopes) { scope in
            scope.category.isEmpty ? "General" : scope.category
        }
        return categorized
            .sorted { $0.key < $1.key }
            .map { (category: $0.key, scopes: $0.value) }
    }

    private var step4ScopesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select the permissions your scripts need")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(selectedScopes.count) scope\(selectedScopes.count == 1 ? "" : "s") selected")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groupedScopes, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            // Category header
                            Text(group.category)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            ForEach(group.scopes) { scope in
                                Toggle(isOn: scopeBinding(for: scope.oauthScope)) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(scope.label)
                                            .font(.callout)
                                        Text(scope.id)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func scopeBinding(for oauthScope: String) -> Binding<Bool> {
        Binding(
            get: { selectedScopes.contains(oauthScope) },
            set: { isOn in
                if isOn { selectedScopes.insert(oauthScope) }
                else { selectedScopes.remove(oauthScope) }
            }
        )
    }

    // MARK: - Actions

    private func saveAPIKey() {
        store.setAPIKey(provider.id, value: apiKey)
        store.refresh()
        closeWindow()
    }

    private func saveCredentials() {
        errorMessage = nil
        store.setClientID(provider.id, value: clientID)
        if !clientSecret.isEmpty {
            store.setClientSecret(provider.id, value: clientSecret)
        }
        credentialsSaved = true
        store.refresh()
    }

    private func connect() async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }

        // Guardar credencials si no s'ha fet
        if !credentialsSaved { saveCredentials() }

        let scopes = Array(selectedScopes)

        do {
            if provider.usesLocalhostCallback {
                let result = try oauth.buildAuthURL(
                    provider: provider,
                    clientID: clientID,
                    scopes: scopes
                )
                NSWorkspace.shared.open(result.url)

                let entry = try await oauth.waitForLocalhostCallback(
                    provider: provider,
                    clientID: clientID,
                    clientSecret: clientSecret,
                    state: result.state,
                    verifier: result.verifier,
                    scopes: scopes
                )
                store.setEntry(provider.id, entry: entry)
            } else {
                let entry = try await oauth.login(
                    provider: provider,
                    clientID: clientID,
                    clientSecret: clientSecret,
                    scopes: scopes
                )
                store.setEntry(provider.id, entry: entry)
            }

            store.refresh()
            closeWindow()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
