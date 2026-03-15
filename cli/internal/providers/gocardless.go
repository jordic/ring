package providers

func init() {
	Register(GoCardless)
}

var GoCardless = Provider{
	ID: "gocardless", Label: "GoCardless Banking",
	Kind: KindAPIKey,
	Setup: SetupGuide{
		DashboardURL: "https://bankaccountdata.gocardless.com/",
		NeedsSecret:  true,
		KeyLabel:     "Secret ID + Secret Key",
		Steps: []string{
			"Create a free account at GoCardless Bank Account Data",
			"Go to Developers → User secrets",
			"Click 'Create new secret'",
			"Copy the Secret ID and Secret Key",
		},
	},
}
