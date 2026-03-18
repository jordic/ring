package main

import (
	"os"

	"github.com/jordic/ring/internal/keychain"
	"github.com/jordic/ring/internal/providers"
	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "ring",
	Short: "Local OAuth & credential manager for macOS",
	Long:  `ring manages OAuth2 tokens, API keys, and credentials in the macOS Keychain.`,
	PersistentPreRun: func(cmd *cobra.Command, args []string) {
		var ids []string
		for _, p := range providers.All {
			ids = append(ids, p.ID)
		}
		keychain.MigrateOldFormat(ids)
	},
}

// Execute runs the root command.
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
