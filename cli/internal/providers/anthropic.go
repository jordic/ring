package providers

func init() {
	Register(Anthropic)
}

var Anthropic = Provider{
	ID: "anthropic", Label: "Anthropic",
	Kind: KindAPIKey,
	Setup: SetupGuide{
		DashboardURL: "https://console.anthropic.com/keys",
		KeyLabel:     "API Key",
		Steps: []string{
			"Click 'Create Key'",
			"Copy the key",
		},
	},
}
