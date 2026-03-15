package providers

func init() {
	Register(Twitter)
}

var Twitter = Provider{
	ID: "twitter", Label: "Twitter / X",
	Kind:            KindOAuth2,
	UsePKCE:         true,
	RefreshStrategy: RefreshProactive,
	AuthURL:         "https://twitter.com/i/oauth2/authorize",
	TokenURL:        "https://api.twitter.com/2/oauth2/token",
	AvailableScopes: []ScopeDefinition{
		{ID: "read", OAuthScope: "tweet.read users.read", Label: "Read tweets and profile"},
		{ID: "write", OAuthScope: "tweet.write", Label: "Post tweets"},
		{ID: "dm:read", OAuthScope: "dm.read", Label: "Read DMs"},
		{ID: "follows:read", OAuthScope: "follows.read", Label: "Read follows"},
		{ID: "follows:write", OAuthScope: "follows.write", Label: "Follow/unfollow"},
		{ID: "offline", OAuthScope: "offline.access", Label: "Offline access (refresh token)"},
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
