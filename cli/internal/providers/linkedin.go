package providers

func init() {
	Register(LinkedIn)
}

var LinkedIn = Provider{
	ID: "linkedin", Label: "LinkedIn",
	Kind:            KindOAuth2,
	UsePKCE:         false,
	RefreshStrategy: RefreshOnExpiry,
	AuthURL:         "https://www.linkedin.com/oauth/v2/authorization",
	TokenURL:        "https://www.linkedin.com/oauth/v2/accessToken",
	AvailableScopes: []ScopeDefinition{
		{ID: "profile", OAuthScope: "r_liteprofile", Label: "Basic profile"},
		{ID: "email", OAuthScope: "r_emailaddress", Label: "Email address"},
		{ID: "posts:write", OAuthScope: "w_member_social", Label: "Post content"},
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
