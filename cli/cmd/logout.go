package main

import (
	"fmt"

	"github.com/jordic/ring/pkg/tokenstore"
	"github.com/spf13/cobra"
)

var logoutCmd = &cobra.Command{
	Use:   "logout <provider>",
	Short: "Remove stored tokens for a provider (keeps client credentials)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		providerID := args[0]
		store := tokenstore.New()

		if err := store.Logout(providerID); err != nil {
			return err
		}

		fmt.Printf("Logged out from %s\n", providerID)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(logoutCmd)
}
