package main

import (
	"fmt"
	"strings"

	"github.com/jordic/ring/internal/providers"
	"github.com/jordic/ring/pkg/tokenstore"
	"github.com/spf13/cobra"
)

var statusCmd = &cobra.Command{
	Use:   "status <provider>",
	Short: "Show detailed status for a provider",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		providerID := args[0]
		store := tokenstore.New()

		st, err := store.Status(providerID)
		if err != nil {
			return err
		}

		p := st.Provider
		fmt.Printf("Provider:    %s (%s)\n", p.Label, p.ID)
		fmt.Printf("Kind:        %s\n", kindLabel(p.Kind))
		fmt.Printf("Configured:  %v\n", st.Configured)
		fmt.Printf("Connected:   %v\n", st.Connected)

		if st.ExpiresAt != nil {
			fmt.Printf("Expires at:  %s\n", st.ExpiresAt.Format("2006-01-02 15:04:05"))
		}

		if st.NeedsRefresh {
			fmt.Printf("Status:      needs refresh\n")
		}

		if p.Kind == providers.KindOAuth2 && len(st.ActiveScopes) > 0 {
			labels := make([]string, len(st.ActiveScopes))
			for i, s := range st.ActiveScopes {
				labels[i] = s.ID
			}
			fmt.Printf("Scopes:      %s\n", strings.Join(labels, ", "))
		}

		if !st.Configured {
			fmt.Printf("\nRun: ring setup %s\n", p.ID)
		} else if p.Kind == providers.KindOAuth2 && !st.Connected {
			fmt.Printf("\nRun: ring login %s\n", p.ID)
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(statusCmd)
}
