package keychain

import (
	"github.com/zalando/go-keyring"
)

const Service = "com.ring.tokenstore"

// Get retrieves a value from the keychain.
func Get(account string) (string, error) {
	return keyring.Get(Service, account)
}

// Set stores a value in the keychain.
func Set(account, value string) error {
	return keyring.Set(Service, account, value)
}

// Delete removes a value from the keychain.
func Delete(account string) error {
	return keyring.Delete(Service, account)
}

// Exists returns true if the key exists in the keychain.
func Exists(account string) bool {
	_, err := keyring.Get(Service, account)
	return err == nil
}

// Get2 retrieves a value from the keychain, returning "" if not found.
func Get2(account string) string {
	v, err := keyring.Get(Service, account)
	if err != nil {
		return ""
	}
	return v
}
