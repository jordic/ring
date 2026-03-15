package main

import (
	"fmt"
	"os"

	"github.com/jordic/ring/internal/keychain"
	"github.com/jordic/ring/pkg/tokenstore"
	"github.com/spf13/cobra"
)

var sessionRefresh bool

var sessionCmd = &cobra.Command{
	Use:   "session <id>",
	Short: "Print the Playwright session file path for a credential set",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		id := args[0]
		store := tokenstore.New()

		if sessionRefresh {
			// Prompt for new session path
			newPath := prompt("Session file path: ")
			if newPath == "" {
				fmt.Fprintln(os.Stderr, "session path cannot be empty")
				os.Exit(1)
			}
			if err := keychain.Set(id+".session_path", newPath); err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
			fmt.Print(newPath)
			return nil
		}

		path, err := store.GetSessionPath(id)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Print(path)
		return nil
	},
}

func init() {
	sessionCmd.Flags().BoolVar(&sessionRefresh, "refresh", false, "Update the session path")
	rootCmd.AddCommand(sessionCmd)
}
