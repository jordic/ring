package providers

func init() {
	Register(Spotify)
}

var Spotify = Provider{
	ID: "spotify", Label: "Spotify",
	Kind:            KindOAuth2,
	UsePKCE:         true,
	RefreshStrategy: RefreshProactive,
	AuthURL:         "https://accounts.spotify.com/authorize",
	TokenURL:        "https://accounts.spotify.com/api/token",
	AvailableScopes: []ScopeDefinition{
		{ID: "playback", OAuthScope: "user-read-playback-state", Label: "Playback state"},
		{ID: "playback:modify", OAuthScope: "user-modify-playback-state", Label: "Control playback"},
		{ID: "library:read", OAuthScope: "user-library-read", Label: "Read library"},
		{ID: "library:modify", OAuthScope: "user-library-modify", Label: "Modify library"},
		{ID: "playlists:read", OAuthScope: "playlist-read-private", Label: "Read playlists"},
		{ID: "playlists:modify", OAuthScope: "playlist-modify-private", Label: "Modify playlists"},
		{ID: "history", OAuthScope: "user-read-recently-played", Label: "Listening history"},
		{ID: "top", OAuthScope: "user-top-read", Label: "Top artists & tracks"},
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
