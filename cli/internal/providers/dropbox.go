package providers

func init() {
	Register(Dropbox)
}

var Dropbox = Provider{
	ID: "dropbox", Label: "Dropbox",
	Kind:            KindOAuth2,
	UsePKCE:         true,
	RefreshStrategy: RefreshProactive,
	AuthURL:         "https://www.dropbox.com/oauth2/authorize",
	TokenURL:        "https://api.dropboxapi.com/oauth2/token",
	AvailableScopes: []ScopeDefinition{
		{ID: "files:read", OAuthScope: "files.content.read", Label: "Read files"},
		{ID: "files:write", OAuthScope: "files.content.write", Label: "Write files"},
		{ID: "sharing:read", OAuthScope: "sharing.read", Label: "Read shared links"},
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
