package providers

func init() {
	Register(Google)
}

var Google = Provider{
	ID: "google", Label: "Google",
	Kind:            KindOAuth2,
	UsePKCE:         true,
	RefreshStrategy: RefreshProactive,
	AuthURL:         "https://accounts.google.com/o/oauth2/v2/auth",
	TokenURL:        "https://oauth2.googleapis.com/token",
	DefaultScopes:   []string{"openid", "email"},
	AvailableScopes: []ScopeDefinition{
		{ID: "gmail.readonly", OAuthScope: "https://www.googleapis.com/auth/gmail.readonly", Label: "Read Gmail"},
		{ID: "gmail.send", OAuthScope: "https://www.googleapis.com/auth/gmail.send", Label: "Send Gmail"},
		{ID: "calendar.events", OAuthScope: "https://www.googleapis.com/auth/calendar.events", Label: "Calendar — events"},
		{ID: "drive.readonly", OAuthScope: "https://www.googleapis.com/auth/drive.readonly", Label: "Drive — read"},
		{ID: "drive.file", OAuthScope: "https://www.googleapis.com/auth/drive.file", Label: "Drive — app files"},
		{ID: "contacts.readonly", OAuthScope: "https://www.googleapis.com/auth/contacts.readonly", Label: "Contacts — read"},
		{ID: "youtube.readonly", OAuthScope: "https://www.googleapis.com/auth/youtube.readonly", Label: "YouTube — read"},
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
