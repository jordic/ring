package providers

import "errors"

type ProviderKind int

const (
	KindOAuth2      ProviderKind = iota
	KindAPIKey
	KindCredentials
)

type RefreshStrategy int

const (
	RefreshNever    RefreshStrategy = iota // GitHub
	RefreshOnExpiry                        // Notion, Figma, LinkedIn
	RefreshProactive                       // Google, Spotify — 5min before expiry
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
	UseDeviceFlow   bool // GitHub
	RefreshStrategy RefreshStrategy
	AvailableScopes []ScopeDefinition
	DefaultScopes   []string
}

// Fixed port for the callback server
const CallbackPort = 9876
const CallbackURI = "http://localhost:9876/callback"

// Actionable errors
var (
	ErrNotConfigured = errors.New("not configured — run: ring setup <provider>")
	ErrNotLoggedIn   = errors.New("not authenticated — run: ring login <provider>")
	ErrScopesMissing = errors.New("required scope not active — run: ring scopes <provider> --add <scope>")
	ErrInvalidClient = errors.New("invalid client_id or client_secret")
	ErrRefreshFailed = errors.New("could not refresh token — please log in again")
)

// Registry of all known providers
var All = map[string]Provider{}

func Register(p Provider) {
	All[p.ID] = p
}

func Get(id string) (Provider, bool) {
	p, ok := All[id]
	return p, ok
}
