package main

import (
	"fmt"
	"os"

	"github.com/jordic/ring/pkg/tokenstore"
	"github.com/spf13/cobra"
)

var tokenRequireScope string

var tokenCmd = &cobra.Command{
	Use:   "token <provider>",
	Short: "Print a valid token for the given provider",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		store := tokenstore.New()
		providerID := args[0]

		var result *tokenstore.TokenResult
		var err error

		if tokenRequireScope != "" {
			result, err = store.GetTokenWithScope(providerID, tokenRequireScope)
		} else {
			result, err = store.GetToken(providerID)
		}

		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}

		// Print ONLY the token — scripts depend on this
		fmt.Print(result.Value)
		return nil
	},
}

func init() {
	tokenCmd.Flags().StringVar(&tokenRequireScope, "require-scope", "", "Fail if this scope is not active")
	rootCmd.AddCommand(tokenCmd)
}
