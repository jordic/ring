package providers

func init() {
	Register(Figma)
}

var Figma = Provider{
	ID: "figma", Label: "Figma",
	Kind:            KindOAuth2,
	UsePKCE:         true,
	RefreshStrategy: RefreshOnExpiry,
	AuthURL:         "https://www.figma.com/oauth",
	TokenURL:        "https://api.figma.com/v1/oauth/token",
	AvailableScopes: []ScopeDefinition{
		{ID: "files:read", OAuthScope: "file_read", Label: "Read files and projects"},
		{ID: "variables:read", OAuthScope: "variables:read", Label: "Read variables"},
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
