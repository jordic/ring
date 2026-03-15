package providers

func init() {
	Register(Discord)
}

var Discord = Provider{
	ID: "discord", Label: "Discord",
	Kind:            KindOAuth2,
	UsePKCE:         true,
	RefreshStrategy: RefreshProactive,
	AuthURL:         "https://discord.com/api/oauth2/authorize",
	TokenURL:        "https://discord.com/api/oauth2/token",
	AvailableScopes: []ScopeDefinition{
		{ID: "identify", OAuthScope: "identify", Label: "Basic profile"},
		{ID: "guilds", OAuthScope: "guilds", Label: "Server list"},
		{ID: "guilds.members", OAuthScope: "guilds.members.read", Label: "Server members"},
		{ID: "messages:read", OAuthScope: "messages.read", Label: "Read messages"},
		{ID: "bot", OAuthScope: "bot", Label: "Add bot to server"},
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
