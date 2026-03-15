package main

import (
	"fmt"
	"os"

	"github.com/jordic/ring/pkg/tokenstore"
	"github.com/spf13/cobra"
)

var usernameCmd = &cobra.Command{
	Use:   "username <id>",
	Short: "Print the stored username for a credential set",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		store := tokenstore.New()
		u, err := store.GetUsername(args[0])
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Print(u)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(usernameCmd)
}
