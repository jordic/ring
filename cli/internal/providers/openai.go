package providers

func init() {
	Register(OpenAI)
}

var OpenAI = Provider{
	ID: "openai", Label: "OpenAI",
	Kind: KindAPIKey,
	Setup: SetupGuide{
		DashboardURL: "https://platform.openai.com/api-keys",
		KeyLabel:     "API Key",
		Steps: []string{
			"Click 'Create new secret key'",
			"Copy the key (shown only once)",
		},
	},
}
