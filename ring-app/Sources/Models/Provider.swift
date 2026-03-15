import Foundation

// MARK: - Enums

enum ProviderKind {
    case oauth2
    case apiKey
    case credentials
}

enum RefreshStrategy {
    case never       // GitHub — tokens don't expire
    case onExpiry    // Notion, Figma, LinkedIn
    case proactive   // Google, Spotify — refresh 5min before expiry
}

// MARK: - Supporting types

struct ScopeDefinition: Identifiable, Hashable {
    let id: String          // "gmail.readonly"
    let oauthScope: String  // "https://www.googleapis.com/auth/gmail.readonly"
    let label: String       // "Read Gmail"
    let description: String
    let category: String    // "Gmail", "Drive", etc. — per agrupar a la UI

    init(id: String, oauthScope: String, label: String, description: String = "", category: String = "") {
        self.id = id
        self.oauthScope = oauthScope
        self.label = label
        self.description = description
        self.category = category
    }
}

struct SetupGuide {
    let dashboardURL: String
    let needsSecret: Bool    // OAuth2: requires client_secret?
    let steps: [String]
    let redirectURI: String  // "http://localhost:9876/callback"
    let keyLabel: String     // APIKey label

    init(
        dashboardURL: String,
        needsSecret: Bool = false,
        steps: [String] = [],
        redirectURI: String = "http://localhost:9876/callback",
        keyLabel: String = "API Key"
    ) {
        self.dashboardURL = dashboardURL
        self.needsSecret = needsSecret
        self.steps = steps
        self.redirectURI = redirectURI
        self.keyLabel = keyLabel
    }
}

// MARK: - Provider

struct Provider: Identifiable {
    let id: String
    let label: String
    let kind: ProviderKind
    let setup: SetupGuide

    // OAuth2 only
    let authURL: String
    let tokenURL: String
    let usePKCE: Bool
    let useDeviceFlow: Bool
    /// Providers que NO accepten custom URL schemes (ex: Google Desktop app).
    /// Usen http://localhost:9876/callback i necessiten un servidor local.
    let usesLocalhostCallback: Bool
    let refreshStrategy: RefreshStrategy
    let availableScopes: [ScopeDefinition]
    let defaultScopes: [String]

    init(
        id: String,
        label: String,
        kind: ProviderKind,
        setup: SetupGuide,
        authURL: String = "",
        tokenURL: String = "",
        usePKCE: Bool = false,
        useDeviceFlow: Bool = false,
        usesLocalhostCallback: Bool = false,
        refreshStrategy: RefreshStrategy = .never,
        availableScopes: [ScopeDefinition] = [],
        defaultScopes: [String] = []
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.setup = setup
        self.authURL = authURL
        self.tokenURL = tokenURL
        self.usePKCE = usePKCE
        self.useDeviceFlow = useDeviceFlow
        self.usesLocalhostCallback = usesLocalhostCallback
        self.refreshStrategy = refreshStrategy
        self.availableScopes = availableScopes
        self.defaultScopes = defaultScopes
    }

    var sfSymbol: String {
        switch id {
        case "github":     return "chevron.left.forwardslash.chevron.right"
        case "google":     return "envelope"
        case "spotify":    return "music.note"
        case "dropbox":    return "archivebox"
        case "notion":     return "doc.text"
        case "figma":      return "paintbrush"
        case "discord":    return "bubble.left.and.bubble.right"
        case "twitter":    return "bird"
        case "linkedin":   return "person.crop.rectangle"
        case "openai":     return "sparkles"
        case "anthropic":  return "brain"
        case "telegram":   return "paperplane"
        case "gocardless": return "creditcard"
        default:           return "key"
        }
    }
}

// MARK: - All Providers

extension Provider {
    static let all: [Provider] = [
        github, google, spotify, dropbox, notion,
        figma, discord, twitter, linkedin,
        openai, anthropic, telegram, gocardless,
    ]

    static func find(_ id: String) -> Provider? {
        all.first { $0.id == id }
    }

    // MARK: OAuth2

    static let github = Provider(
        id: "github", label: "GitHub",
        kind: .oauth2,
        setup: SetupGuide(
            dashboardURL: "https://github.com/settings/developers",
            needsSecret: true,
            steps: [
                "Go to Settings → Developer Settings → OAuth Apps",
                "Click 'New OAuth App'",
                "Homepage URL: http://localhost",
                "Callback URL: http://localhost:9876/callback",
                "Copy the Client ID and generate a Client Secret",
            ],
            redirectURI: "http://localhost:9876/callback"
        ),
        authURL: "https://github.com/login/oauth/authorize",
        tokenURL: "https://github.com/login/oauth/access_token",
        usesLocalhostCallback: true,
        refreshStrategy: .never,
        availableScopes: [
            ScopeDefinition(id: "repo",      oauthScope: "repo",        label: "Repositories (r/w)"),
            ScopeDefinition(id: "repo:read", oauthScope: "public_repo", label: "Public repositories"),
            ScopeDefinition(id: "gist",      oauthScope: "gist",        label: "Gists"),
            ScopeDefinition(id: "read:user", oauthScope: "read:user",   label: "User profile"),
            ScopeDefinition(id: "workflow",  oauthScope: "workflow",    label: "GitHub Actions"),
        ]
    )

    static let google = Provider(
        id: "google", label: "Google",
        kind: .oauth2,
        setup: SetupGuide(
            dashboardURL: "https://console.cloud.google.com/apis/credentials",
            needsSecret: true,
            steps: [
                "Create a new project (or use an existing one)",
                "Go to APIs & Services → Credentials",
                "Create 'OAuth 2.0 Client ID' → type 'Desktop app'",
                "Add redirect URI: http://localhost:9876/callback",
                "Copy the Client ID and Client Secret",
            ],
            redirectURI: "http://localhost:9876/callback"
        ),
        authURL: "https://accounts.google.com/o/oauth2/v2/auth",
        tokenURL: "https://oauth2.googleapis.com/token",
        usePKCE: true,
        usesLocalhostCallback: true,
        refreshStrategy: .proactive,
        availableScopes: [
            // Gmail
            ScopeDefinition(id: "gmail.readonly",  oauthScope: "https://www.googleapis.com/auth/gmail.readonly",  label: "Read emails",        category: "Gmail"),
            ScopeDefinition(id: "gmail.send",      oauthScope: "https://www.googleapis.com/auth/gmail.send",      label: "Send emails",        category: "Gmail"),
            ScopeDefinition(id: "gmail.compose",   oauthScope: "https://www.googleapis.com/auth/gmail.compose",   label: "Compose & drafts",   category: "Gmail"),
            ScopeDefinition(id: "gmail.modify",    oauthScope: "https://www.googleapis.com/auth/gmail.modify",    label: "Read & modify",      category: "Gmail"),
            ScopeDefinition(id: "gmail.labels",    oauthScope: "https://www.googleapis.com/auth/gmail.labels",    label: "Manage labels",      category: "Gmail"),

            // Calendar
            ScopeDefinition(id: "calendar.readonly",        oauthScope: "https://www.googleapis.com/auth/calendar.readonly",        label: "View calendars",    category: "Calendar"),
            ScopeDefinition(id: "calendar.events",          oauthScope: "https://www.googleapis.com/auth/calendar.events",          label: "Manage events",     category: "Calendar"),
            ScopeDefinition(id: "calendar.events.readonly", oauthScope: "https://www.googleapis.com/auth/calendar.events.readonly", label: "View events",       category: "Calendar"),
            ScopeDefinition(id: "calendar.freebusy",        oauthScope: "https://www.googleapis.com/auth/calendar.freebusy",        label: "View availability", category: "Calendar"),

            // Drive
            ScopeDefinition(id: "drive.readonly",          oauthScope: "https://www.googleapis.com/auth/drive.readonly",          label: "View all files",     category: "Drive"),
            ScopeDefinition(id: "drive.file",              oauthScope: "https://www.googleapis.com/auth/drive.file",              label: "App-created files",  category: "Drive"),
            ScopeDefinition(id: "drive",                   oauthScope: "https://www.googleapis.com/auth/drive",                   label: "Full access",        category: "Drive"),
            ScopeDefinition(id: "drive.appdata",           oauthScope: "https://www.googleapis.com/auth/drive.appdata",           label: "App config data",    category: "Drive"),
            ScopeDefinition(id: "drive.metadata.readonly", oauthScope: "https://www.googleapis.com/auth/drive.metadata.readonly", label: "View file metadata", category: "Drive"),

            // Sheets
            ScopeDefinition(id: "spreadsheets.readonly", oauthScope: "https://www.googleapis.com/auth/spreadsheets.readonly", label: "View spreadsheets",   category: "Sheets"),
            ScopeDefinition(id: "spreadsheets",          oauthScope: "https://www.googleapis.com/auth/spreadsheets",          label: "Manage spreadsheets", category: "Sheets"),

            // Docs
            ScopeDefinition(id: "documents.readonly", oauthScope: "https://www.googleapis.com/auth/documents.readonly", label: "View documents",   category: "Docs"),
            ScopeDefinition(id: "documents",          oauthScope: "https://www.googleapis.com/auth/documents",          label: "Manage documents", category: "Docs"),

            // Tasks
            ScopeDefinition(id: "tasks.readonly", oauthScope: "https://www.googleapis.com/auth/tasks.readonly", label: "View tasks",   category: "Tasks"),
            ScopeDefinition(id: "tasks",          oauthScope: "https://www.googleapis.com/auth/tasks",          label: "Manage tasks", category: "Tasks"),

            // Contacts
            ScopeDefinition(id: "contacts.readonly", oauthScope: "https://www.googleapis.com/auth/contacts.readonly", label: "View contacts",   category: "Contacts"),
            ScopeDefinition(id: "contacts",          oauthScope: "https://www.googleapis.com/auth/contacts",          label: "Manage contacts", category: "Contacts"),

            // YouTube
            ScopeDefinition(id: "youtube.readonly", oauthScope: "https://www.googleapis.com/auth/youtube.readonly", label: "View account",   category: "YouTube"),
            ScopeDefinition(id: "youtube.upload",   oauthScope: "https://www.googleapis.com/auth/youtube.upload",   label: "Upload videos",  category: "YouTube"),
            ScopeDefinition(id: "youtube",          oauthScope: "https://www.googleapis.com/auth/youtube",          label: "Full access",    category: "YouTube"),

            // Photos
            ScopeDefinition(id: "photos.appendonly",  oauthScope: "https://www.googleapis.com/auth/photoslibrary.appendonly",              label: "Upload photos",   category: "Photos"),
            ScopeDefinition(id: "photos.readonly",    oauthScope: "https://www.googleapis.com/auth/photoslibrary.readonly.appcreateddata", label: "View app photos", category: "Photos"),

            // Cloud Platform
            ScopeDefinition(id: "cloud-platform.readonly", oauthScope: "https://www.googleapis.com/auth/cloud-platform.read-only", label: "View GCP resources",   category: "Cloud"),
            ScopeDefinition(id: "cloud-platform",          oauthScope: "https://www.googleapis.com/auth/cloud-platform",           label: "Manage GCP resources", category: "Cloud"),
            ScopeDefinition(id: "bigquery",                oauthScope: "https://www.googleapis.com/auth/bigquery",                 label: "BigQuery access",      category: "Cloud"),

            // Analytics
            ScopeDefinition(id: "analytics.readonly", oauthScope: "https://www.googleapis.com/auth/analytics.readonly", label: "View analytics", category: "Analytics"),
        ],
        defaultScopes: ["openid", "email"]
    )

    static let spotify = Provider(
        id: "spotify", label: "Spotify",
        kind: .oauth2,
        setup: SetupGuide(
            dashboardURL: "https://developer.spotify.com/dashboard",
            needsSecret: true,
            steps: [
                "Click 'Create app'",
                "Name: anything (e.g. 'My Scripts')",
                "Redirect URI: ring://oauth/callback",
                "Copy the Client ID and Client Secret",
            ],
            redirectURI: "ring://oauth/callback"
        ),
        authURL: "https://accounts.spotify.com/authorize",
        tokenURL: "https://accounts.spotify.com/api/token",
        usePKCE: true,
        refreshStrategy: .proactive,
        availableScopes: [
            ScopeDefinition(id: "playback",          oauthScope: "user-read-playback-state",   label: "Playback state"),
            ScopeDefinition(id: "playback:modify",   oauthScope: "user-modify-playback-state", label: "Control playback"),
            ScopeDefinition(id: "library:read",      oauthScope: "user-library-read",          label: "Read library"),
            ScopeDefinition(id: "library:modify",    oauthScope: "user-library-modify",        label: "Modify library"),
            ScopeDefinition(id: "playlists:read",    oauthScope: "playlist-read-private",      label: "Read playlists"),
            ScopeDefinition(id: "playlists:modify",  oauthScope: "playlist-modify-private",    label: "Modify playlists"),
            ScopeDefinition(id: "history",           oauthScope: "user-read-recently-played",  label: "Listening history"),
            ScopeDefinition(id: "top",               oauthScope: "user-top-read",              label: "Top artists & tracks"),
        ]
    )

    static let dropbox = Provider(
        id: "dropbox", label: "Dropbox",
        kind: .oauth2,
        setup: SetupGuide(
            dashboardURL: "https://www.dropbox.com/developers/apps",
            needsSecret: true,
            steps: [
                "Create a new app → 'Scoped access' → 'Full Dropbox'",
                "In Settings: Redirect URI: ring://oauth/callback",
                "Copy App Key (Client ID) and App Secret",
            ],
            redirectURI: "ring://oauth/callback"
        ),
        authURL: "https://www.dropbox.com/oauth2/authorize",
        tokenURL: "https://api.dropboxapi.com/oauth2/token",
        usePKCE: true,
        refreshStrategy: .proactive,
        availableScopes: [
            ScopeDefinition(id: "files:read",   oauthScope: "files.content.read",  label: "Read files"),
            ScopeDefinition(id: "files:write",  oauthScope: "files.content.write", label: "Write files"),
            ScopeDefinition(id: "sharing:read", oauthScope: "sharing.read",        label: "Read shared links"),
        ]
    )

    static let notion = Provider(
        id: "notion", label: "Notion",
        kind: .oauth2,
        setup: SetupGuide(
            dashboardURL: "https://www.notion.so/my-integrations",
            needsSecret: true,
            steps: [
                "Click 'New integration' → 'Public integration'",
                "Redirect URI: ring://oauth/callback",
                "Copy OAuth Client ID and Client Secret",
            ],
            redirectURI: "ring://oauth/callback"
        ),
        authURL: "https://api.notion.com/v1/oauth/authorize",
        tokenURL: "https://api.notion.com/v1/oauth/token",
        usePKCE: true,
        refreshStrategy: .onExpiry,
        availableScopes: [
            ScopeDefinition(id: "full", oauthScope: "", label: "Full workspace access"),
        ]
    )

    static let figma = Provider(
        id: "figma", label: "Figma",
        kind: .oauth2,
        setup: SetupGuide(
            dashboardURL: "https://www.figma.com/developers/apps",
            needsSecret: true,
            steps: [
                "Click 'Create a new app'",
                "Callback URL: ring://oauth/callback",
                "Copy the Client ID and Client Secret",
            ],
            redirectURI: "ring://oauth/callback"
        ),
        authURL: "https://www.figma.com/oauth",
        tokenURL: "https://api.figma.com/v1/oauth/token",
        usePKCE: true,
        refreshStrategy: .onExpiry,
        availableScopes: [
            ScopeDefinition(id: "files:read",      oauthScope: "file_read",       label: "Read files and projects"),
            ScopeDefinition(id: "variables:read",  oauthScope: "variables:read",  label: "Read variables"),
            ScopeDefinition(id: "variables:write", oauthScope: "variables:write", label: "Modify variables"),
        ]
    )

    static let discord = Provider(
        id: "discord", label: "Discord",
        kind: .oauth2,
        setup: SetupGuide(
            dashboardURL: "https://discord.com/developers/applications",
            needsSecret: true,
            steps: [
                "Create a new application",
                "Go to OAuth2 → General",
                "Add Redirect: ring://oauth/callback",
                "Copy Client ID and Client Secret",
            ],
            redirectURI: "ring://oauth/callback"
        ),
        authURL: "https://discord.com/api/oauth2/authorize",
        tokenURL: "https://discord.com/api/oauth2/token",
        usePKCE: true,
        refreshStrategy: .proactive,
        availableScopes: [
            ScopeDefinition(id: "identify",       oauthScope: "identify",            label: "Basic profile"),
            ScopeDefinition(id: "guilds",          oauthScope: "guilds",              label: "Server list"),
            ScopeDefinition(id: "guilds.members",  oauthScope: "guilds.members.read", label: "Server members"),
            ScopeDefinition(id: "messages:read",   oauthScope: "messages.read",       label: "Read messages"),
            ScopeDefinition(id: "bot",             oauthScope: "bot",                 label: "Add bot to server"),
        ]
    )

    static let twitter = Provider(
        id: "twitter", label: "Twitter / X",
        kind: .oauth2,
        setup: SetupGuide(
            dashboardURL: "https://developer.twitter.com/en/portal/dashboard",
            needsSecret: true,
            steps: [
                "Create a new project and app",
                "In 'User authentication settings': enable OAuth 2.0",
                "App type: 'Native App'",
                "Callback URI: ring://oauth/callback",
                "Copy Client ID and Client Secret",
            ],
            redirectURI: "ring://oauth/callback"
        ),
        authURL: "https://twitter.com/i/oauth2/authorize",
        tokenURL: "https://api.twitter.com/2/oauth2/token",
        usePKCE: true,
        refreshStrategy: .proactive,
        availableScopes: [
            ScopeDefinition(id: "read",          oauthScope: "tweet.read users.read", label: "Read tweets and profile"),
            ScopeDefinition(id: "write",         oauthScope: "tweet.write",           label: "Post tweets"),
            ScopeDefinition(id: "dm:read",       oauthScope: "dm.read",               label: "Read DMs"),
            ScopeDefinition(id: "follows:read",  oauthScope: "follows.read",          label: "Read follows"),
            ScopeDefinition(id: "follows:write", oauthScope: "follows.write",         label: "Follow/unfollow"),
            ScopeDefinition(id: "offline",       oauthScope: "offline.access",        label: "Offline access (refresh token)"),
        ]
    )

    static let linkedin = Provider(
        id: "linkedin", label: "LinkedIn",
        kind: .oauth2,
        setup: SetupGuide(
            dashboardURL: "https://www.linkedin.com/developers/apps",
            needsSecret: true,
            steps: [
                "Create a new app",
                "In the Auth tab: Redirect URL: ring://oauth/callback",
                "Copy Client ID and Client Secret",
            ],
            redirectURI: "ring://oauth/callback"
        ),
        authURL: "https://www.linkedin.com/oauth/v2/authorization",
        tokenURL: "https://www.linkedin.com/oauth/v2/accessToken",
        usePKCE: false,
        refreshStrategy: .onExpiry,
        availableScopes: [
            ScopeDefinition(id: "profile",     oauthScope: "r_liteprofile",   label: "Basic profile"),
            ScopeDefinition(id: "email",       oauthScope: "r_emailaddress",  label: "Email address"),
            ScopeDefinition(id: "posts:write", oauthScope: "w_member_social", label: "Post content"),
        ]
    )

    // MARK: API Key

    static let openai = Provider(
        id: "openai", label: "OpenAI",
        kind: .apiKey,
        setup: SetupGuide(
            dashboardURL: "https://platform.openai.com/api-keys",
            steps: [
                "Click 'Create new secret key'",
                "Copy the key (shown only once)",
            ],
            keyLabel: "API Key"
        )
    )

    static let anthropic = Provider(
        id: "anthropic", label: "Anthropic",
        kind: .apiKey,
        setup: SetupGuide(
            dashboardURL: "https://console.anthropic.com/keys",
            steps: [
                "Click 'Create Key'",
                "Copy the key",
            ],
            keyLabel: "API Key"
        )
    )

    static let telegram = Provider(
        id: "telegram", label: "Telegram",
        kind: .apiKey,
        setup: SetupGuide(
            dashboardURL: "https://t.me/botfather",
            steps: [
                "Open @BotFather on Telegram",
                "Send /newbot and follow the instructions",
                "Copy the token (format: 123456:ABC-DEF...)",
            ],
            keyLabel: "Bot Token"
        )
    )

    static let gocardless = Provider(
        id: "gocardless", label: "GoCardless Banking",
        kind: .apiKey,
        setup: SetupGuide(
            dashboardURL: "https://bankaccountdata.gocardless.com/",
            needsSecret: true,
            steps: [
                "Create a free account at GoCardless Bank Account Data",
                "Go to Developers → User secrets",
                "Click 'Create new secret'",
                "Copy the Secret ID and Secret Key",
            ],
            keyLabel: "Secret ID + Secret Key"
        )
    )
}
