package providers

func init() {
	Register(Telegram)
}

var Telegram = Provider{
	ID: "telegram", Label: "Telegram",
	Kind: KindAPIKey,
	Setup: SetupGuide{
		DashboardURL: "https://t.me/botfather",
		KeyLabel:     "Bot Token",
		Steps: []string{
			"Open @BotFather on Telegram",
			"Send /newbot and follow the instructions",
			"Copy the token (format: 123456:ABC-DEF...)",
		},
	},
}
