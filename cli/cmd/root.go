package main

import (
	"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "ring",
	Short: "Local OAuth & credential manager for macOS",
	Long:  `ring manages OAuth2 tokens, API keys, and credentials in the macOS Keychain.`,
}

// Execute runs the root command.
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
