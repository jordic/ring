package providers

func init() {
	Register(GitHub)
}

var GitHub = Provider{
	ID: "github", Label: "GitHub",
	Kind:            KindOAuth2,
	UseDeviceFlow:   true,
	UsePKCE:         false,
	RefreshStrategy: RefreshNever,
	AuthURL:         "https://github.com/login/device/code",
	TokenURL:        "https://github.com/login/oauth/access_token",
	AvailableScopes: []ScopeDefinition{
		{ID: "repo", OAuthScope: "repo", Label: "Repositories (r/w)"},
		{ID: "repo:read", OAuthScope: "public_repo", Label: "Public repositories"},
		{ID: "gist", OAuthScope: "gist", Label: "Gists"},
		{ID: "read:user", OAuthScope: "read:user", Label: "User profile"},
		{ID: "workflow", OAuthScope: "workflow", Label: "GitHub Actions"},
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
