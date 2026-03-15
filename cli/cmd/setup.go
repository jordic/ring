package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/jordic/ring/internal/providers"
	"github.com/jordic/ring/pkg/tokenstore"
	"github.com/spf13/cobra"
)

var setupKey string

var setupCmd = &cobra.Command{
	Use:   "setup <provider>",
	Short: "Configure a provider with client credentials or API key",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		providerID := args[0]
		store := tokenstore.New()

		p, ok := providers.Get(providerID)
		if !ok {
			return fmt.Errorf("unknown provider: %s\nRun 'ring list' to see available providers", providerID)
		}

		// Print setup guide
		fmt.Printf("\n=== Setup: %s ===\n", p.Label)
		if p.Setup.DashboardURL != "" {
			fmt.Printf("Dashboard: %s\n", p.Setup.DashboardURL)
		}
		fmt.Println()
		for i, step := range p.Setup.Steps {
			fmt.Printf("  %d. %s\n", i+1, step)
		}
		fmt.Println()

		creds := tokenstore.Credentials{}

		switch p.Kind {
		case providers.KindAPIKey:
			if setupKey != "" {
				creds.APIKey = setupKey
			} else {
				label := p.Setup.KeyLabel
				if label == "" {
					label = "API Key"
				}
				creds.APIKey = prompt(label + ": ")
			}

		case providers.KindOAuth2:
			creds.ClientID = prompt("Client ID: ")
			if p.Setup.NeedsSecret {
				creds.ClientSecret = prompt("Client Secret: ")
			}
		}

		if err := store.Configure(providerID, creds); err != nil {
			return err
		}

		fmt.Printf("\n%s configured successfully.\n", p.Label)

		if p.Kind == providers.KindOAuth2 {
			fmt.Printf("Run 'ring login %s' to authenticate.\n", providerID)
		}

		return nil
	},
}

func prompt(label string) string {
	reader := bufio.NewReader(os.Stdin)
	fmt.Print(label)
	text, _ := reader.ReadString('\n')
	return strings.TrimSpace(text)
}

func init() {
	setupCmd.Flags().StringVar(&setupKey, "key", "", "API key value (non-interactive)")
	rootCmd.AddCommand(setupCmd)
}
