package main

import (
	"fmt"

	"github.com/jordic/ring/pkg/tokenstore"
	"github.com/spf13/cobra"
)

var removeCmd = &cobra.Command{
	Use:   "remove <provider>",
	Short: "Remove all keychain entries for a provider",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		providerID := args[0]
		store := tokenstore.New()

		if err := store.Remove(providerID); err != nil {
			return err
		}

		fmt.Printf("All data for '%s' removed from keychain.\n", providerID)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(removeCmd)
}
