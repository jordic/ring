package main

import (
	"fmt"
	"strings"

	"github.com/jordic/ring/internal/providers"
	"github.com/jordic/ring/pkg/tokenstore"
	"github.com/spf13/cobra"
)

var scopesAdd string

var scopesCmd = &cobra.Command{
	Use:   "scopes <provider>",
	Short: "Show or add OAuth2 scopes for a provider",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		providerID := args[0]
		store := tokenstore.New()

		if scopesAdd != "" {
			newScopes := strings.Split(scopesAdd, ",")
			for i := range newScopes {
				newScopes[i] = strings.TrimSpace(newScopes[i])
			}
			if err := store.AddScopes(providerID, newScopes); err != nil {
				return err
			}
			fmt.Printf("Scopes updated for %s. Added: %s\n", providerID, scopesAdd)
			return nil
		}

		// Show scopes
		p, ok := providers.Get(providerID)
		if !ok {
			return fmt.Errorf("unknown provider: %s", providerID)
		}

		st, err := store.Status(providerID)
		if err != nil {
			return err
		}

		activeSet := make(map[string]bool)
		for _, s := range st.ActiveScopes {
			activeSet[s.ID] = true
		}

		fmt.Printf("Scopes for %s:\n\n", p.Label)
		fmt.Printf("  %-20s %-8s %s\n", "ID", "ACTIVE", "LABEL")
		fmt.Printf("  %-20s %-8s %s\n", "--", "------", "-----")
		for _, def := range p.AvailableScopes {
			active := " "
			if activeSet[def.ID] {
				active = "✓"
			}
			fmt.Printf("  %-20s %-8s %s\n", def.ID, active, def.Label)
		}

		fmt.Printf("\nTo add a scope: ring scopes %s --add <scope>\n", providerID)
		return nil
	},
}

func init() {
	scopesCmd.Flags().StringVar(&scopesAdd, "add", "", "Comma-separated scopes to add (triggers re-login)")
	rootCmd.AddCommand(scopesCmd)
}
