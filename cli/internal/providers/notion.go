package providers

func init() {
	Register(Notion)
}

var Notion = Provider{
	ID: "notion", Label: "Notion",
	Kind:            KindOAuth2,
	UsePKCE:         true,
	RefreshStrategy: RefreshOnExpiry,
	AuthURL:         "https://api.notion.com/v1/oauth/authorize",
	TokenURL:        "https://api.notion.com/v1/oauth/token",
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
