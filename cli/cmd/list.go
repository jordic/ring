package main

import (
	"fmt"
	"sort"

	"github.com/jordic/ring/internal/providers"
	"github.com/jordic/ring/pkg/tokenstore"
	"github.com/spf13/cobra"
)

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List all providers and their status",
	RunE: func(cmd *cobra.Command, args []string) error {
		store := tokenstore.New()
		statuses, err := store.StatusAll()
		if err != nil {
			return err
		}

		// Sort by provider ID for stable output
		sort.Slice(statuses, func(i, j int) bool {
			return statuses[i].Provider.ID < statuses[j].Provider.ID
		})

		fmt.Printf("%-15s %-12s %-12s %s\n", "PROVIDER", "KIND", "STATUS", "EXPIRES")
		fmt.Printf("%-15s %-12s %-12s %s\n", "--------", "----", "------", "-------")

		for _, st := range statuses {
			kind := kindLabel(st.Provider.Kind)
			status := statusLabel(st)
			expires := ""
			if st.ExpiresAt != nil {
				expires = st.ExpiresAt.Format("2006-01-02 15:04")
			}
			fmt.Printf("%-15s %-12s %-12s %s\n", st.Provider.ID, kind, status, expires)
		}

		return nil
	},
}

func kindLabel(k providers.ProviderKind) string {
	switch k {
	case providers.KindOAuth2:
		return "oauth2"
	case providers.KindAPIKey:
		return "api-key"
	case providers.KindCredentials:
		return "credentials"
	}
	return "unknown"
}

func statusLabel(st *tokenstore.ProviderStatus) string {
	if !st.Configured {
		return "not-configured"
	}
	if !st.Connected {
		return "not-logged-in"
	}
	if st.NeedsRefresh {
		return "needs-refresh"
	}
	return "ok"
}

func init() {
	rootCmd.AddCommand(listCmd)
}
