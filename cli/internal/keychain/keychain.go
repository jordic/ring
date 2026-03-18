package keychain

import (
	"encoding/json"
	"errors"
	"strings"
	"sync"

	"github.com/zalando/go-keyring"
)

const Service = "com.ring.tokenstore"
const storeAccount = "data"

var ErrNotFound = errors.New("keychain: not found")

var (
	mu     sync.Mutex
	cache  map[string]string
	loaded bool
)

func load() map[string]string {
	if loaded {
		return cache
	}
	loaded = true
	raw, err := keyring.Get(Service, storeAccount)
	if err != nil {
		cache = make(map[string]string)
		return cache
	}
	var m map[string]string
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		cache = make(map[string]string)
		return cache
	}
	cache = m
	return cache
}

func save() error {
	data, err := json.Marshal(cache)
	if err != nil {
		return err
	}
	return keyring.Set(Service, storeAccount, string(data))
}

// Get retrieves a value by key.
func Get(account string) (string, error) {
	mu.Lock()
	defer mu.Unlock()
	m := load()
	v, ok := m[account]
	if !ok {
		return "", ErrNotFound
	}
	return v, nil
}

// Set stores a value by key.
func Set(account, value string) error {
	mu.Lock()
	defer mu.Unlock()
	m := load()
	m[account] = value
	return save()
}

// Delete removes a key.
func Delete(account string) error {
	mu.Lock()
	defer mu.Unlock()
	m := load()
	delete(m, account)
	return save()
}

// Exists returns true if the key exists.
func Exists(account string) bool {
	mu.Lock()
	defer mu.Unlock()
	m := load()
	_, ok := m[account]
	return ok
}

// Get2 retrieves a value, returning "" if not found.
func Get2(account string) string {
	mu.Lock()
	defer mu.Unlock()
	m := load()
	return m[account]
}

// MigrateOldFormat reads individual keychain items for the given provider IDs
// and consolidates them into the single JSON blob. Call once at startup.
func MigrateOldFormat(providerIDs []string) {
	mu.Lock()
	defer mu.Unlock()
	m := load()
	if len(m) > 0 {
		return // already have data, skip migration
	}

	providerSuffixes := []string{
		".client_id", ".client_secret",
		".access_token", ".refresh_token", ".expires_at", ".scopes",
		".api_key", ".secret_id", ".secret_key",
	}

	credSuffixes := []string{
		".username", ".password", ".totp_secret", ".session_path",
	}

	migrated := false
	var oldKeys []string

	// Migrate provider keys
	for _, pid := range providerIDs {
		for _, s := range providerSuffixes {
			key := pid + s
			if v, err := keyring.Get(Service, key); err == nil && v != "" {
				m[key] = v
				oldKeys = append(oldKeys, key)
				migrated = true
			}
		}
	}

	// Migrate credentials.list and associated credential keys
	if list, err := keyring.Get(Service, "credentials.list"); err == nil && list != "" {
		m["credentials.list"] = list
		oldKeys = append(oldKeys, "credentials.list")
		migrated = true
		for _, id := range strings.Split(list, ",") {
			if id == "" {
				continue
			}
			for _, s := range credSuffixes {
				key := id + s
				if v, err := keyring.Get(Service, key); err == nil && v != "" {
					m[key] = v
					oldKeys = append(oldKeys, key)
				}
			}
		}
	}

	if migrated {
		_ = save()
		for _, key := range oldKeys {
			_ = keyring.Delete(Service, key)
		}
	}
}
