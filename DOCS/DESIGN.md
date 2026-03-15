# ring — Design Document

> Local OAuth & credential manager for macOS.  
> Two independent components sharing the same Keychain.

---

## Overview

`ring` manages OAuth2 tokens, API Keys and credentials centrally in the macOS Keychain. Bash/Python scripts and Playwright automations always get a fresh token with a single call, without handling expiration, refresh or secrets.

```
┌─────────────────────────────────────────────┐
│           Ring.app  (SwiftUI)               │
│  Setup, login, scope management, UI status  │
└─────────────────────┬───────────────────────┘
                      │ reads/writes
                      ▼
┌─────────────────────────────────────────────┐
│            macOS KEYCHAIN                   │
│           shared source of truth            │
└─────────────────────┬───────────────────────┘
                      │ reads
                      ▼
┌─────────────────────────────────────────────┐
│           ring  (Go CLI)                    │
│  token, login, setup, status — in scripts   │
└─────────────────────────────────────────────┘
```

---

## Repository Structure

```
/
├── cli/                        # Go — ring binary
│   ├── cmd/
│   │   ├── root.go
│   │   ├── token.go
│   │   ├── login.go
│   │   ├── logout.go
│   │   ├── setup.go
│   │   ├── status.go
│   │   ├── list.go
│   │   ├── scopes.go
│   │   ├── session.go
│   │   ├── username.go
│   │   ├── password.go
│   │   └── totp.go
│   ├── internal/
│   │   ├── keychain/
│   │   │   └── keychain.go
│   │   ├── oauth/
│   │   │   ├── pkce.go
│   │   │   ├── device.go
│   │   │   └── server.go       # localhost callback server
│   │   ├── token/
│   │   │   └── manager.go      # get-or-refresh logic
│   │   ├── totp/
│   │   │   └── totp.go
│   │   └── providers/
│   │       ├── provider.go     # base types
│   │       ├── github.go
│   │       ├── google.go
│   │       ├── spotify.go
│   │       ├── dropbox.go
│   │       ├── notion.go
│   │       ├── figma.go
│   │       ├── discord.go
│   │       ├── twitter.go
│   │       ├── linkedin.go
│   │       ├── openai.go
│   │       ├── anthropic.go
│   │       ├── telegram.go
│   │       └── gocardless.go
│   ├── pkg/
│   │   └── tokenstore/
│   │       └── store.go        # public API
│   ├── go.mod
│   └── Makefile
│
├── ring-app/                   # SwiftUI — Ring.app
│   ├── Ring.xcodeproj
│   ├── Ring/
│   │   ├── App.swift
│   │   ├── KeychainStore.swift
│   │   ├── Models/
│   │   │   ├── Provider.swift
│   │   │   ├── TokenEntry.swift
│   │   │   └── Scope.swift
│   │   ├── Views/
│   │   │   ├── MenuBarView.swift
│   │   │   ├── ProviderRowView.swift
│   │   │   ├── SetupWizardView.swift
│   │   │   └── ScopesView.swift
│   │   └── OAuth/
│   │       ├── OAuthFlow.swift         # ASWebAuthenticationSession
│   │       └── TOTPGenerator.swift
│   └── Package.swift
│
├── docs/
│   └── DESIGN.md               # this file
└── README.md
```

---

## Keychain — Key Convention

**Service:** `com.ring.tokenstore`  
Both components (Go CLI and SwiftUI) must use exactly these keys.

```
# OAuth2 — client configuration
{provider}.client_id
{provider}.client_secret            # only if NeedsSecret = true

# OAuth2 — tokens
{provider}.access_token
{provider}.refresh_token            # empty if RefreshStrategy = Never
{provider}.expires_at               # RFC3339, empty if it doesn't expire
{provider}.scopes                   # "scope1,scope2,scope3"

# API Key
{provider}.api_key

# Credentials (free-form instances)
{id}.username
{id}.password
{id}.totp_secret                    # base32, optional
{id}.session_path                   # path to Playwright session file

# Global credentials index
credentials.list                    # "netflix,mybank,work-jira"
```

---

## Go Types

### internal/providers/provider.go

```go
package providers

import "time"

type ProviderKind int

const (
    KindOAuth2       ProviderKind = iota
    KindAPIKey
    KindCredentials
)

type RefreshStrategy int

const (
    RefreshNever      RefreshStrategy = iota // GitHub
    RefreshOnExpiry                          // Notion, Figma, LinkedIn
    RefreshProactive                         // Google, Spotify — 5min before expiry
)

type ScopeDefinition struct {
    ID          string // "gmail.readonly"
    OAuthScope  string // "https://www.googleapis.com/auth/gmail.readonly"
    Label       string // "Read Gmail"
    Description string
}

type SetupGuide struct {
    DashboardURL string
    NeedsSecret  bool     // OAuth2: requires client_secret?
    Steps        []string // step-by-step instructions
    RedirectURI  string   // "http://localhost:9876/callback"
    KeyLabel     string   // APIKey: "API Key", "Secret Key", "Bot Token"...
}

type Provider struct {
    ID    string
    Label string
    Kind  ProviderKind
    Setup SetupGuide

    // OAuth2 only
    AuthURL         string
    TokenURL        string
    UsePKCE         bool
    UseDeviceFlow   bool            // GitHub
    RefreshStrategy RefreshStrategy
    AvailableScopes []ScopeDefinition
    DefaultScopes   []string
}

// Fixed port for the callback server
const CallbackPort = 9876
const CallbackURI  = "http://localhost:9876/callback"
```

### internal/keychain/keychain.go

```go
package keychain

const Service = "com.ring.tokenstore"

func Get(account string) (string, error)
func Set(account, value string) error
func Delete(account string) error
func Exists(account string) bool
```

### pkg/tokenstore/store.go

```go
package tokenstore

import "time"

type TokenResult struct {
    Value     string       // AT or API Key — always a string
    ExpiresAt *time.Time   // nil for API Keys and GitHub
    Provider  string
    Kind      providers.ProviderKind
}

type Credentials struct {
    ClientID     string // OAuth2
    ClientSecret string // OAuth2 (if NeedsSecret)
    APIKey       string // KindAPIKey
}

type ProviderStatus struct {
    Provider     providers.Provider
    Configured   bool               // has client_id or api_key?
    Connected    bool               // has a valid token?
    ActiveScopes []providers.ScopeDefinition
    ExpiresAt    *time.Time
    NeedsRefresh bool
}

type Store interface {
    // Common
    GetToken(providerID string) (*TokenResult, error)
    GetTokenWithScope(providerID, scope string) (*TokenResult, error)
    Status(providerID string) (*ProviderStatus, error)
    StatusAll() ([]*ProviderStatus, error)
    Remove(providerID string) error
    Configure(providerID string, creds Credentials) error

    // OAuth2 only
    Login(providerID string, scopes []string) error
    AddScopes(providerID string, newScopes []string) error
    Logout(providerID string) error

    // Credentials only
    GetUsername(id string) (string, error)
    GetPassword(id string) (string, error)
    GetTOTP(id string) (string, error)        // generates 6-digit code
    GetSessionPath(id string) (string, error) // refreshes if needed
}
```

---

## OAuth2 Providers

### GitHub
```go
var GitHub = Provider{
    ID: "github", Label: "GitHub",
    Kind:            KindOAuth2,
    UseDeviceFlow:   true,
    UsePKCE:         false,
    RefreshStrategy: RefreshNever,
    AuthURL:  "https://github.com/login/device/code",
    TokenURL: "https://github.com/login/oauth/access_token",
    AvailableScopes: []ScopeDefinition{
        {ID: "repo",       OAuthScope: "repo",          Label: "Repositories (r/w)"},
        {ID: "repo:read",  OAuthScope: "public_repo",   Label: "Public repositories"},
        {ID: "gist",       OAuthScope: "gist",          Label: "Gists"},
        {ID: "read:user",  OAuthScope: "read:user",     Label: "User profile"},
        {ID: "workflow",   OAuthScope: "workflow",      Label: "GitHub Actions"},
    },
    Setup: SetupGuide{
        DashboardURL: "https://github.com/settings/developers",
        NeedsSecret:  true,
        Steps: []string{
            "Go to Settings → Developer Settings → OAuth Apps",
            "Click 'New OAuth App'",
            "Homepage URL: http://localhost",
            "Callback URL: http://localhost:9876/callback",
            "Copy the Client ID and generate a Client Secret",
        },
    },
}
```

### Google
```go
var Google = Provider{
    ID: "google", Label: "Google",
    Kind:            KindOAuth2,
    UsePKCE:         true,
    RefreshStrategy: RefreshProactive,
    AuthURL:  "https://accounts.google.com/o/oauth2/v2/auth",
    TokenURL: "https://oauth2.googleapis.com/token",
    DefaultScopes: []string{"openid", "email"},
    AvailableScopes: []ScopeDefinition{
        {ID: "gmail.readonly",    OAuthScope: "https://www.googleapis.com/auth/gmail.readonly",     Label: "Read Gmail"},
        {ID: "gmail.send",        OAuthScope: "https://www.googleapis.com/auth/gmail.send",         Label: "Send Gmail"},
        {ID: "calendar.events",   OAuthScope: "https://www.googleapis.com/auth/calendar.events",    Label: "Calendar — events"},
        {ID: "drive.readonly",    OAuthScope: "https://www.googleapis.com/auth/drive.readonly",     Label: "Drive — read"},
        {ID: "drive.file",        OAuthScope: "https://www.googleapis.com/auth/drive.file",         Label: "Drive — app files"},
        {ID: "contacts.readonly", OAuthScope: "https://www.googleapis.com/auth/contacts.readonly",  Label: "Contacts — read"},
        {ID: "youtube.readonly",  OAuthScope: "https://www.googleapis.com/auth/youtube.readonly",   Label: "YouTube — read"},
    },
    Setup: SetupGuide{
        DashboardURL: "https://console.cloud.google.com/apis/credentials",
        NeedsSecret:  true,
        Steps: []string{
            "Create a new project (or use an existing one)",
            "Go to APIs & Services → Credentials",
            "Create 'OAuth 2.0 Client ID' → type 'Desktop app'",
            "Add redirect URI: http://localhost:9876/callback",
            "Copy the Client ID and Client Secret",
        },
        RedirectURI: CallbackURI,
    },
}
```

### Spotify
```go
var Spotify = Provider{
    ID: "spotify", Label: "Spotify",
    Kind:            KindOAuth2,
    UsePKCE:         true,
    RefreshStrategy: RefreshProactive,
    AuthURL:  "https://accounts.spotify.com/authorize",
    TokenURL: "https://accounts.spotify.com/api/token",
    AvailableScopes: []ScopeDefinition{
        {ID: "playback",         OAuthScope: "user-read-playback-state",   Label: "Playback state"},
        {ID: "playback:modify",  OAuthScope: "user-modify-playback-state", Label: "Control playback"},
        {ID: "library:read",     OAuthScope: "user-library-read",          Label: "Read library"},
        {ID: "library:modify",   OAuthScope: "user-library-modify",        Label: "Modify library"},
        {ID: "playlists:read",   OAuthScope: "playlist-read-private",      Label: "Read playlists"},
        {ID: "playlists:modify", OAuthScope: "playlist-modify-private",    Label: "Modify playlists"},
        {ID: "history",          OAuthScope: "user-read-recently-played",  Label: "Listening history"},
        {ID: "top",              OAuthScope: "user-top-read",              Label: "Top artists & tracks"},
    },
    Setup: SetupGuide{
        DashboardURL: "https://developer.spotify.com/dashboard",
        NeedsSecret:  true,
        Steps: []string{
            "Click 'Create app'",
            "Name: anything (e.g. 'My Scripts')",
            "Redirect URI: http://localhost:9876/callback",
            "Copy the Client ID and Client Secret",
        },
        RedirectURI: CallbackURI,
    },
}
```

### Dropbox
```go
var Dropbox = Provider{
    ID: "dropbox", Label: "Dropbox",
    Kind:            KindOAuth2,
    UsePKCE:         true,
    RefreshStrategy: RefreshProactive,
    AuthURL:  "https://www.dropbox.com/oauth2/authorize",
    TokenURL: "https://api.dropboxapi.com/oauth2/token",
    AvailableScopes: []ScopeDefinition{
        {ID: "files:read",   OAuthScope: "files.content.read",  Label: "Read files"},
        {ID: "files:write",  OAuthScope: "files.content.write", Label: "Write files"},
        {ID: "sharing:read", OAuthScope: "sharing.read",        Label: "Read shared links"},
    },
    Setup: SetupGuide{
        DashboardURL: "https://www.dropbox.com/developers/apps",
        NeedsSecret:  true,
        Steps: []string{
            "Create a new app → 'Scoped access' → 'Full Dropbox'",
            "In Settings: Redirect URI: http://localhost:9876/callback",
            "Copy App Key (Client ID) and App Secret",
        },
        RedirectURI: CallbackURI,
    },
}
```

### Notion
```go
var Notion = Provider{
    ID: "notion", Label: "Notion",
    Kind:            KindOAuth2,
    UsePKCE:         true,
    RefreshStrategy: RefreshOnExpiry,
    AuthURL:  "https://api.notion.com/v1/oauth/authorize",
    TokenURL: "https://api.notion.com/v1/oauth/token",
    AvailableScopes: []ScopeDefinition{
        {ID: "full", OAuthScope: "", Label: "Full workspace access"},
    },
    Setup: SetupGuide{
        DashboardURL: "https://www.notion.so/my-integrations",
        NeedsSecret:  true,
        Steps: []string{
            "Click 'New integration' → 'Public integration'",
            "Redirect URI: http://localhost:9876/callback",
            "Copy OAuth Client ID and Client Secret",
        },
        RedirectURI: CallbackURI,
    },
}
```

### Figma
```go
var Figma = Provider{
    ID: "figma", Label: "Figma",
    Kind:            KindOAuth2,
    UsePKCE:         true,
    RefreshStrategy: RefreshOnExpiry,
    AuthURL:  "https://www.figma.com/oauth",
    TokenURL: "https://api.figma.com/v1/oauth/token",
    AvailableScopes: []ScopeDefinition{
        {ID: "files:read",      OAuthScope: "file_read",       Label: "Read files and projects"},
        {ID: "variables:read",  OAuthScope: "variables:read",  Label: "Read variables"},
        {ID: "variables:write", OAuthScope: "variables:write", Label: "Modify variables"},
    },
    Setup: SetupGuide{
        DashboardURL: "https://www.figma.com/developers/apps",
        NeedsSecret:  true,
        Steps: []string{
            "Click 'Create a new app'",
            "Callback URL: http://localhost:9876/callback",
            "Copy the Client ID and Client Secret",
        },
        RedirectURI: CallbackURI,
    },
}
```

### Discord
```go
var Discord = Provider{
    ID: "discord", Label: "Discord",
    Kind:            KindOAuth2,
    UsePKCE:         true,
    RefreshStrategy: RefreshProactive,
    AuthURL:  "https://discord.com/api/oauth2/authorize",
    TokenURL: "https://discord.com/api/oauth2/token",
    AvailableScopes: []ScopeDefinition{
        {ID: "identify",        OAuthScope: "identify",            Label: "Basic profile"},
        {ID: "guilds",          OAuthScope: "guilds",              Label: "Server list"},
        {ID: "guilds.members",  OAuthScope: "guilds.members.read", Label: "Server members"},
        {ID: "messages:read",   OAuthScope: "messages.read",       Label: "Read messages"},
        {ID: "bot",             OAuthScope: "bot",                 Label: "Add bot to server"},
    },
    Setup: SetupGuide{
        DashboardURL: "https://discord.com/developers/applications",
        NeedsSecret:  true,
        Steps: []string{
            "Create a new application",
            "Go to OAuth2 → General",
            "Add Redirect: http://localhost:9876/callback",
            "Copy Client ID and Client Secret",
        },
        RedirectURI: CallbackURI,
    },
}
```

### Twitter/X
```go
var Twitter = Provider{
    ID: "twitter", Label: "Twitter / X",
    Kind:            KindOAuth2,
    UsePKCE:         true,
    RefreshStrategy: RefreshProactive,
    AuthURL:  "https://twitter.com/i/oauth2/authorize",
    TokenURL: "https://api.twitter.com/2/oauth2/token",
    AvailableScopes: []ScopeDefinition{
        {ID: "read",           OAuthScope: "tweet.read users.read", Label: "Read tweets and profile"},
        {ID: "write",          OAuthScope: "tweet.write",           Label: "Post tweets"},
        {ID: "dm:read",        OAuthScope: "dm.read",               Label: "Read DMs"},
        {ID: "follows:read",   OAuthScope: "follows.read",          Label: "Read follows"},
        {ID: "follows:write",  OAuthScope: "follows.write",         Label: "Follow/unfollow"},
        {ID: "offline",        OAuthScope: "offline.access",        Label: "Offline access (refresh token)"},
    },
    Setup: SetupGuide{
        DashboardURL: "https://developer.twitter.com/en/portal/dashboard",
        NeedsSecret:  true,
        Steps: []string{
            "Create a new project and app",
            "In 'User authentication settings': enable OAuth 2.0",
            "App type: 'Native App'",
            "Callback URI: http://localhost:9876/callback",
            "Copy Client ID and Client Secret",
        },
        RedirectURI: CallbackURI,
    },
}
```

### LinkedIn
```go
var LinkedIn = Provider{
    ID: "linkedin", Label: "LinkedIn",
    Kind:            KindOAuth2,
    UsePKCE:         false,
    RefreshStrategy: RefreshOnExpiry,
    AuthURL:  "https://www.linkedin.com/oauth/v2/authorization",
    TokenURL: "https://www.linkedin.com/oauth/v2/accessToken",
    AvailableScopes: []ScopeDefinition{
        {ID: "profile",      OAuthScope: "r_liteprofile",   Label: "Basic profile"},
        {ID: "email",        OAuthScope: "r_emailaddress",  Label: "Email address"},
        {ID: "posts:write",  OAuthScope: "w_member_social", Label: "Post content"},
    },
    Setup: SetupGuide{
        DashboardURL: "https://www.linkedin.com/developers/apps",
        NeedsSecret:  true,
        Steps: []string{
            "Create a new app",
            "In the Auth tab: Redirect URL: http://localhost:9876/callback",
            "Copy Client ID and Client Secret",
        },
        RedirectURI: CallbackURI,
    },
}
```

---

## API Key Providers

### OpenAI
```go
var OpenAI = Provider{
    ID: "openai", Label: "OpenAI",
    Kind: KindAPIKey,
    Setup: SetupGuide{
        DashboardURL: "https://platform.openai.com/api-keys",
        KeyLabel: "API Key",
        Steps: []string{
            "Click 'Create new secret key'",
            "Copy the key (shown only once)",
        },
    },
}
```

### Anthropic
```go
var Anthropic = Provider{
    ID: "anthropic", Label: "Anthropic",
    Kind: KindAPIKey,
    Setup: SetupGuide{
        DashboardURL: "https://console.anthropic.com/keys",
        KeyLabel: "API Key",
        Steps: []string{
            "Click 'Create Key'",
            "Copy the key",
        },
    },
}
```

### Telegram
```go
var Telegram = Provider{
    ID: "telegram", Label: "Telegram",
    Kind: KindAPIKey,
    Setup: SetupGuide{
        DashboardURL: "https://t.me/botfather",
        KeyLabel: "Bot Token",
        Steps: []string{
            "Open @BotFather on Telegram",
            "Send /newbot and follow the instructions",
            "Copy the token (format: 123456:ABC-DEF...)",
        },
    },
}
```

### GoCardless (Banking)
```go
var GoCardless = Provider{
    ID: "gocardless", Label: "GoCardless Banking",
    Kind: KindAPIKey,
    Setup: SetupGuide{
        DashboardURL: "https://bankaccountdata.gocardless.com/",
        NeedsSecret:  true,
        KeyLabel:     "Secret ID + Secret Key",
        Steps: []string{
            "Create a free account at GoCardless Bank Account Data",
            "Go to Developers → User secrets",
            "Click 'Create new secret'",
            "Copy the Secret ID and Secret Key",
        },
    },
}
```

---

## CLI — Full Command Reference

```
# Information
ring list                              # all providers and their status
ring status <provider>                 # detailed provider info

# Setup — OAuth2 and APIKey (interactive wizard)
ring setup <provider>
ring setup <provider> --key <val>      # direct APIKey (for scripts)

# OAuth2
ring login <provider> [--scopes s1,s2]
ring logout <provider>
ring scopes <provider>                 # show active and available scopes
ring scopes <provider> --add <scope>   # re-login with additional scope

# Get token — OAuth2 and APIKey (identical usage from scripts)
ring token <provider> [--require-scope <scope>]

# Credentials (free-form instances)
ring credentials add <id>             # wizard: url, user, pass, totp
ring credentials remove <id>
ring username <id>                    # → stdout
ring password <id>                    # → stdout
ring totp <id>                        # → 6-digit code generated now
ring session <id>                     # → path to Playwright session file
ring session <id> --refresh           # force re-login

# Remove everything for a provider
ring remove <provider>
```

### Usage from scripts

```bash
# Bash
TOKEN=$(ring token spotify)
curl -H "Authorization: Bearer $TOKEN" https://api.spotify.com/v1/me

# With scope validation
TOKEN=$(ring token google --require-scope drive.readonly)

# Credentials
USER=$(ring username mybank)
PASS=$(ring password mybank)
CODE=$(ring totp mybank)

# Playwright
SESSION=$(ring session mybank)
```

```python
# Python
import subprocess

def get_token(provider):
    return subprocess.check_output(["ring", "token", provider]).decode().strip()

token = get_token("spotify")
```

```typescript
// Playwright
import { execSync } from 'child_process'
import { chromium } from 'playwright'

const sessionPath = execSync('ring session mybank').toString().trim()
const context = await chromium.launch().then(b =>
    b.newContext({ storageState: sessionPath })
)
```

---

## Errors — Actionable Messages

```go
var (
    ErrNotConfigured = errors.New("not configured — run: ring setup <provider>")
    ErrNotLoggedIn   = errors.New("not authenticated — run: ring login <provider>")
    ErrScopesMissing = errors.New("required scope not active — run: ring scopes <provider> --add <scope>")
    ErrInvalidClient = errors.New("invalid client_id or client_secret")
    ErrRefreshFailed = errors.New("could not refresh token — please log in again")
)
```

---

## SwiftUI — Main Components

### App.swift
```swift
@main
struct RingApp: App {
    var body: some Scene {
        MenuBarExtra("ring", systemImage: "key.fill") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
```

### KeychainStore.swift
```swift
// Exact mirror of the Go CLI keys
class KeychainStore: ObservableObject {
    static let service = "com.ring.tokenstore"

    func getString(_ account: String) -> String?
    func setString(_ account: String, value: String)
    func delete(_ account: String)

    func getEntry(_ providerID: String) -> TokenEntry?
    func setEntry(_ providerID: String, entry: TokenEntry)

    func isConfigured(_ providerID: String) -> Bool
    func isConnected(_ providerID: String) -> Bool
}
```

### OAuthFlow.swift
```swift
// Uses ASWebAuthenticationSession — NO localhost server needed
class OAuthFlow: NSObject, ASWebAuthenticationPresentationContextProviding {
    func login(provider: Provider, scopes: [String]) async throws -> TokenEntry
    func addScopes(provider: Provider, currentScopes: [String], newScopes: [String]) async throws -> TokenEntry
    func refresh(provider: Provider, refreshToken: String) async throws -> TokenEntry
}
```

---

## Dependencies

### Go (cli/go.mod)
```
github.com/spf13/cobra          v1.8+   # CLI commands
github.com/zalando/go-keyring   v0.2+   # macOS Keychain
golang.org/x/oauth2             latest  # OAuth2 + PKCE
github.com/pkg/browser          v0.2+   # Open browser
github.com/pquerna/otp          v1.4+   # TOTP
```

### Swift (ring-app/Package.swift)
```
// Native frameworks (no SPM needed):
// Security, AuthenticationServices, SwiftUI, UserNotifications

// Single external dependency:
// swift-otp — TOTP generation
```

---

## Implementation Phases

```
Phase 1 — Go Core
  1. internal/keychain     → get/set/delete/exists
  2. internal/providers    → all providers (types + instances)
  3. internal/oauth/pkce   → PKCE flow + localhost callback server
  4. internal/oauth/device → Device Flow (GitHub)
  5. internal/totp         → 6-digit code generation
  6. internal/token        → get-or-refresh (Proactive/OnExpiry/Never)
  7. pkg/tokenstore        → unified Store

Phase 2 — CLI
  8.  cmd/token            → ring token <provider>
  9.  cmd/login            → ring login <provider>
  10. cmd/setup            → interactive wizard
  11. cmd/status + list    → information commands
  12. cmd/scopes           → scope management
  13. cmd/credentials      → username/password/totp/session

Phase 3 — Ring.app SwiftUI
  14. KeychainStore.swift  → read/write keychain
  15. Models               → Provider, TokenEntry, Scope
  16. OAuthFlow.swift      → ASWebAuthenticationSession
  17. SetupWizardView      → per-provider onboarding
  18. MenuBarView          → main view with sections
  19. ScopesView           → per-provider scope management

Phase 4 — Distribution
  20. Homebrew formula     → CLI (brew install ring)
  21. DMG + signing        → Ring.app
  22. GitHub Actions CI/CD → build, test, automated release
```

---

## Distribution

### Homebrew
```ruby
class Ring < Formula
  desc "Local OAuth & credential manager for macOS"
  homepage "https://github.com/you/ring"
  url "https://github.com/you/ring/releases/download/v1.0.0/ring-darwin-arm64.tar.gz"

  def install
    bin.install "ring"
  end
end
```

### Makefile
```makefile
build-cli:
	cd cli && GOOS=darwin GOARCH=arm64 go build -o dist/ring-arm64 ./cmd
	cd cli && GOOS=darwin GOARCH=amd64 go build -o dist/ring-amd64 ./cmd

build-app:
	xcodebuild -project ring-app/Ring.xcodeproj \
	           -scheme Ring \
	           -configuration Release \
	           archive -archivePath dist/Ring.xcarchive

release: build-cli build-app
	# create DMG, tar.gz, GitHub Release
```

---

*Last updated: design finalised, ready to implement.*  
*Recommended order: Phase 1 → Phase 2 → Phase 3 → Phase 4*