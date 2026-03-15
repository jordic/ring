package main

import (
	"fmt"
	"strings"

	"github.com/jordic/ring/internal/keychain"
	"github.com/spf13/cobra"
)

var credentialsCmd = &cobra.Command{
	Use:   "credentials",
	Short: "Manage credential sets (username/password/TOTP/session)",
}

var credAddCmd = &cobra.Command{
	Use:   "add <id>",
	Short: "Add or update a credential set",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		id := args[0]

		fmt.Printf("Adding credentials for '%s'\n\n", id)

		username := prompt("Username: ")
		if username != "" {
			if err := keychain.Set(id+".username", username); err != nil {
				return err
			}
		}

		password := prompt("Password: ")
		if password != "" {
			if err := keychain.Set(id+".password", password); err != nil {
				return err
			}
		}

		totpSecret := prompt("TOTP secret (base32, leave empty to skip): ")
		if totpSecret != "" {
			totpSecret = strings.TrimSpace(totpSecret)
			if err := keychain.Set(id+".totp_secret", totpSecret); err != nil {
				return err
			}
		}

		// Update the global credentials index
		updateCredentialsList(id, true)

		fmt.Printf("\nCredentials for '%s' saved.\n", id)
		return nil
	},
}

var credRemoveCmd = &cobra.Command{
	Use:   "remove <id>",
	Short: "Remove a credential set",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		id := args[0]

		keys := []string{
			id + ".username",
			id + ".password",
			id + ".totp_secret",
			id + ".session_path",
		}
		for _, k := range keys {
			_ = keychain.Delete(k)
		}

		updateCredentialsList(id, false)

		fmt.Printf("Credentials for '%s' removed.\n", id)
		return nil
	},
}

// updateCredentialsList adds or removes an id from the global credentials index.
func updateCredentialsList(id string, add bool) {
	current := keychain.Get2("credentials.list")
	ids := []string{}
	if current != "" {
		ids = strings.Split(current, ",")
	}

	if add {
		for _, existing := range ids {
			if existing == id {
				return // already in list
			}
		}
		ids = append(ids, id)
	} else {
		filtered := ids[:0]
		for _, existing := range ids {
			if existing != id {
				filtered = append(filtered, existing)
			}
		}
		ids = filtered
	}

	_ = keychain.Set("credentials.list", strings.Join(ids, ","))
}

func init() {
	credentialsCmd.AddCommand(credAddCmd)
	credentialsCmd.AddCommand(credRemoveCmd)
	rootCmd.AddCommand(credentialsCmd)
}
