package main

import (
	"fmt"
	"os"

	"github.com/jordic/ring/pkg/tokenstore"
	"github.com/spf13/cobra"
)

var passwordCmd = &cobra.Command{
	Use:   "password <id>",
	Short: "Print the stored password for a credential set",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		store := tokenstore.New()
		p, err := store.GetPassword(args[0])
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Print(p)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(passwordCmd)
}
