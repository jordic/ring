package main

import (
	"fmt"
	"os"

	"github.com/jordic/ring/pkg/tokenstore"
	"github.com/spf13/cobra"
)

var totpCmd = &cobra.Command{
	Use:   "totp <id>",
	Short: "Generate a 6-digit TOTP code for a credential set",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		store := tokenstore.New()
		code, err := store.GetTOTP(args[0])
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Print(code)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(totpCmd)
}
