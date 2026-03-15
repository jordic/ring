package main

import (
	"fmt"
	"strings"

	"github.com/jordic/ring/pkg/tokenstore"
	"github.com/spf13/cobra"
)

var loginScopes string

var loginCmd = &cobra.Command{
	Use:   "login <provider>",
	Short: "Authenticate with an OAuth2 provider",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		providerID := args[0]
		store := tokenstore.New()

		var scopes []string
		if loginScopes != "" {
			scopes = strings.Split(loginScopes, ",")
			for i := range scopes {
				scopes[i] = strings.TrimSpace(scopes[i])
			}
		}

		if err := store.Login(providerID, scopes); err != nil {
			return err
		}

		fmt.Printf("Successfully logged in to %s\n", providerID)
		return nil
	},
}

func init() {
	loginCmd.Flags().StringVar(&loginScopes, "scopes", "", "Comma-separated list of scopes to request")
	rootCmd.AddCommand(loginCmd)
}
