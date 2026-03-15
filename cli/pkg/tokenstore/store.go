package tokenstore

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/jordic/ring/internal/keychain"
	oauthpkg "github.com/jordic/ring/internal/oauth"
	"github.com/jordic/ring/internal/providers"
	"github.com/jordic/ring/internal/token"
	"github.com/jordic/ring/internal/totp"
	"github.com/pkg/browser"
)

// TokenResult is what callers receive when requesting a token.
type TokenResult struct {
	Value     string     // AT or API Key — always a string
	ExpiresAt *time.Time // nil for API Keys and GitHub
	Provider  string
	Kind      providers.ProviderKind
}

// Credentials holds the OAuth2 / API Key client configuration.
type Credentials struct {
	ClientID     string // OAuth2
	ClientSecret string // OAuth2 (if NeedsSecret)
	APIKey       string // KindAPIKey
}

// ProviderStatus describes the current state of a provider.
type ProviderStatus struct {
	Provider     providers.Provider
	Configured   bool // has client_id or api_key?
	Connected    bool // has a valid token?
	ActiveScopes []providers.ScopeDefinition
	ExpiresAt    *time.Time
	NeedsRefresh bool
}

// Store is the unified interface for all ring operations.
type Store interface {
	// Common
	GetToken(providerID string) (*TokenResult, error)
	GetTokenWithScope(providerID, scope string) (*TokenResult, error)
	Status(providerID string) (*ProviderStatus, error)
	StatusAll() ([]*ProviderStatus, error)
	Remove(providerID string) error
	Configure(providerID string, creds Credentials) error

	// OAuth2 only
	Login(providerID string, scopes []string) error
	AddScopes(providerID string, newScopes []string) error
	Logout(providerID string) error

	// Credentials only
	GetUsername(id string) (string, error)
	GetPassword(id string) (string, error)
	GetTOTP(id string) (string, error)
	GetSessionPath(id string) (string, error)
}

type store struct{}

// New returns the default Store implementation.
func New() Store {
	return &store{}
}

// GetToken returns a valid token for the given provider, refreshing if needed.
func (s *store) GetToken(providerID string) (*TokenResult, error) {
	p, ok := providers.Get(providerID)
	if !ok {
		return nil, fmt.Errorf("unknown provider: %s", providerID)
	}

	switch p.Kind {
	case providers.KindAPIKey:
		return s.getAPIKeyToken(p)
	case providers.KindOAuth2:
		return s.getOAuth2Token(p)
	default:
		return nil, fmt.Errorf("provider %s does not support tokens", providerID)
	}
}

func (s *store) getAPIKeyToken(p providers.Provider) (*TokenResult, error) {
	key, err := keychain.Get(p.ID + ".api_key")
	if err != nil {
		// GoCardless stores secret_id + secret_key
		if p.Setup.NeedsSecret {
			secretID, err2 := keychain.Get(p.ID + ".secret_id")
			if err2 != nil {
				return nil, fmt.Errorf("%w: %s", providers.ErrNotConfigured, p.ID)
			}
			return &TokenResult{Value: secretID, Provider: p.ID, Kind: p.Kind}, nil
		}
		return nil, fmt.Errorf("%w: %s", providers.ErrNotConfigured, p.ID)
	}
	return &TokenResult{Value: key, Provider: p.ID, Kind: p.Kind}, nil
}

func (s *store) getOAuth2Token(p providers.Provider) (*TokenResult, error) {
	if !keychain.Exists(p.ID + ".client_id") {
		return nil, fmt.Errorf("%w: %s", providers.ErrNotConfigured, p.ID)
	}

	td, err := token.GetOrRefresh(p)
	if err != nil {
		return nil, err
	}

	return &TokenResult{
		Value:     td.AccessToken,
		ExpiresAt: td.ExpiresAt,
		Provider:  p.ID,
		Kind:      p.Kind,
	}, nil
}

// GetTokenWithScope returns a token and validates that the scope is active.
func (s *store) GetTokenWithScope(providerID, scope string) (*TokenResult, error) {
	p, ok := providers.Get(providerID)
	if !ok {
		return nil, fmt.Errorf("unknown provider: %s", providerID)
	}

	td, err := token.Load(p.ID)
	if err != nil {
		return nil, err
	}

	found := false
	for _, s2 := range td.Scopes {
		if s2 == scope {
			found = true
			break
		}
	}
	if !found {
		return nil, fmt.Errorf("%w: %s for %s", providers.ErrScopesMissing, scope, providerID)
	}

	return s.GetToken(providerID)
}

// Status returns the current status of a provider.
func (s *store) Status(providerID string) (*ProviderStatus, error) {
	p, ok := providers.Get(providerID)
	if !ok {
		return nil, fmt.Errorf("unknown provider: %s", providerID)
	}

	status := &ProviderStatus{Provider: p}

	switch p.Kind {
	case providers.KindAPIKey:
		status.Configured = keychain.Exists(p.ID+".api_key") || keychain.Exists(p.ID+".secret_id")
		status.Connected = status.Configured
	case providers.KindOAuth2:
		status.Configured = keychain.Exists(p.ID + ".client_id")
		status.Connected = keychain.Exists(p.ID + ".access_token")

		if status.Connected {
			td, err := token.Load(p.ID)
			if err == nil {
				status.ExpiresAt = td.ExpiresAt
				status.NeedsRefresh = token.NeedsRefresh(td, p.RefreshStrategy)

				// Resolve active scopes
				for _, scopeID := range td.Scopes {
					for _, def := range p.AvailableScopes {
						if def.ID == scopeID || def.OAuthScope == scopeID {
							status.ActiveScopes = append(status.ActiveScopes, def)
							break
						}
					}
				}
			}
		}
	}

	return status, nil
}

// StatusAll returns the status for every known provider.
func (s *store) StatusAll() ([]*ProviderStatus, error) {
	var results []*ProviderStatus
	for _, p := range providers.All {
		st, err := s.Status(p.ID)
		if err != nil {
			continue
		}
		results = append(results, st)
	}
	return results, nil
}

// Remove deletes all keychain keys for a provider.
func (s *store) Remove(providerID string) error {
	keys := []string{
		providerID + ".client_id",
		providerID + ".client_secret",
		providerID + ".access_token",
		providerID + ".refresh_token",
		providerID + ".expires_at",
		providerID + ".scopes",
		providerID + ".api_key",
		providerID + ".secret_id",
		providerID + ".secret_key",
	}
	for _, k := range keys {
		_ = keychain.Delete(k) // ignore not-found errors
	}
	return nil
}

// Configure stores OAuth2 client credentials or API key.
func (s *store) Configure(providerID string, creds Credentials) error {
	p, ok := providers.Get(providerID)
	if !ok {
		return fmt.Errorf("unknown provider: %s", providerID)
	}

	switch p.Kind {
	case providers.KindAPIKey:
		if creds.APIKey == "" {
			return fmt.Errorf("API key is required for %s", providerID)
		}
		return keychain.Set(providerID+".api_key", creds.APIKey)

	case providers.KindOAuth2:
		if creds.ClientID == "" {
			return fmt.Errorf("client_id is required for %s", providerID)
		}
		if err := keychain.Set(providerID+".client_id", creds.ClientID); err != nil {
			return err
		}
		if creds.ClientSecret != "" {
			return keychain.Set(providerID+".client_secret", creds.ClientSecret)
		}
	}
	return nil
}

// Login performs the OAuth2 login flow for the given provider.
func (s *store) Login(providerID string, scopes []string) error {
	p, ok := providers.Get(providerID)
	if !ok {
		return fmt.Errorf("unknown provider: %s", providerID)
	}
	if p.Kind != providers.KindOAuth2 {
		return fmt.Errorf("%s is not an OAuth2 provider", providerID)
	}

	clientID, err := keychain.Get(p.ID + ".client_id")
	if err != nil {
		return fmt.Errorf("%w: %s", providers.ErrNotConfigured, providerID)
	}
	clientSecret := keychain.Get2(p.ID + ".client_secret")

	// Merge with default scopes
	allScopes := mergeScopes(p.DefaultScopes, scopes)

	if p.UseDeviceFlow {
		return s.loginDevice(p, clientID, allScopes)
	}
	return s.loginPKCE(p, clientID, clientSecret, allScopes)
}

func (s *store) loginDevice(p providers.Provider, clientID string, scopes []string) error {
	dcr, err := oauthpkg.RequestDeviceCode(p.AuthURL, clientID, scopes)
	if err != nil {
		return err
	}

	fmt.Printf("\nOpen this URL to authorise: %s\n", dcr.VerificationURI)
	fmt.Printf("Enter code: %s\n\n", dcr.UserCode)
	fmt.Println("Waiting for authorisation...")

	dtr, err := oauthpkg.PollDeviceToken(p.TokenURL, clientID, dcr.DeviceCode, dcr.Interval)
	if err != nil {
		return err
	}

	td := &token.TokenData{
		AccessToken: dtr.AccessToken,
	}
	if dtr.Scope != "" {
		td.Scopes = strings.Split(dtr.Scope, ",")
	} else {
		td.Scopes = scopes
	}

	return token.Save(p.ID, td)
}

func (s *store) loginPKCE(p providers.Provider, clientID, clientSecret string, scopes []string) error {
	// Build auth URL
	state, err := generateState()
	if err != nil {
		return err
	}

	params := url.Values{}
	params.Set("client_id", clientID)
	params.Set("response_type", "code")
	params.Set("redirect_uri", oauthpkg.CallbackURI)
	params.Set("state", state)
	if len(scopes) > 0 {
		params.Set("scope", strings.Join(scopes, " "))
	}

	var verifier string
	if p.UsePKCE {
		verifier, err = oauthpkg.GenerateVerifier()
		if err != nil {
			return err
		}
		params.Set("code_challenge", oauthpkg.GenerateChallenge(verifier))
		params.Set("code_challenge_method", "S256")
	}

	authURL := p.AuthURL + "?" + params.Encode()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	resultCh, err := oauthpkg.StartCallbackServer(ctx)
	if err != nil {
		return fmt.Errorf("failed to start callback server: %w", err)
	}

	fmt.Printf("\nOpening browser for authorisation...\n")
	fmt.Printf("If the browser does not open, visit:\n%s\n\n", authURL)
	_ = browser.OpenURL(authURL)

	result := <-resultCh
	if result.Error != "" {
		return fmt.Errorf("authorisation failed: %s", result.Error)
	}
	if result.State != state {
		return fmt.Errorf("state mismatch — possible CSRF attack")
	}

	// Exchange code for token
	td, err := exchangeCode(p, clientID, clientSecret, result.Code, verifier)
	if err != nil {
		return err
	}
	td.Scopes = scopes

	return token.Save(p.ID, td)
}

// exchangeCode exchanges an OAuth2 authorization code for tokens.
func exchangeCode(p providers.Provider, clientID, clientSecret, code, verifier string) (*token.TokenData, error) {
	data := url.Values{}
	data.Set("grant_type", "authorization_code")
	data.Set("code", code)
	data.Set("redirect_uri", oauthpkg.CallbackURI)
	data.Set("client_id", clientID)
	if clientSecret != "" {
		data.Set("client_secret", clientSecret)
	}
	if verifier != "" {
		data.Set("code_verifier", verifier)
	}

	return token.Exchange(p.TokenURL, clientID, clientSecret, data)
}

// AddScopes re-authenticates with the union of existing + new scopes.
func (s *store) AddScopes(providerID string, newScopes []string) error {
	p, ok := providers.Get(providerID)
	if !ok {
		return fmt.Errorf("unknown provider: %s", providerID)
	}

	td, _ := token.Load(p.ID)
	var existing []string
	if td != nil {
		existing = td.Scopes
	}

	merged := mergeScopes(existing, newScopes)
	return s.Login(providerID, merged)
}

// Logout removes the access/refresh tokens but keeps client credentials.
func (s *store) Logout(providerID string) error {
	keys := []string{
		providerID + ".access_token",
		providerID + ".refresh_token",
		providerID + ".expires_at",
		providerID + ".scopes",
	}
	for _, k := range keys {
		_ = keychain.Delete(k)
	}
	return nil
}

// GetUsername returns the stored username for a credential set.
func (s *store) GetUsername(id string) (string, error) {
	u, err := keychain.Get(id + ".username")
	if err != nil {
		return "", fmt.Errorf("no username found for '%s' — run: ring credentials add %s", id, id)
	}
	return u, nil
}

// GetPassword returns the stored password for a credential set.
func (s *store) GetPassword(id string) (string, error) {
	p, err := keychain.Get(id + ".password")
	if err != nil {
		return "", fmt.Errorf("no password found for '%s' — run: ring credentials add %s", id, id)
	}
	return p, nil
}

// GetTOTP generates a 6-digit TOTP code for the given credential set.
func (s *store) GetTOTP(id string) (string, error) {
	secret, err := keychain.Get(id + ".totp_secret")
	if err != nil {
		return "", fmt.Errorf("no TOTP secret found for '%s' — run: ring credentials add %s", id, id)
	}
	return totp.Generate(secret)
}

// GetSessionPath returns the Playwright session file path for the given id.
func (s *store) GetSessionPath(id string) (string, error) {
	path, err := keychain.Get(id + ".session_path")
	if err != nil {
		return "", fmt.Errorf("no session found for '%s' — run: ring session %s --refresh", id, id)
	}
	return path, nil
}

// --- helpers ---

func mergeScopes(existing, newScopes []string) []string {
	seen := make(map[string]bool)
	var result []string
	for _, s := range existing {
		if !seen[s] {
			seen[s] = true
			result = append(result, s)
		}
	}
	for _, s := range newScopes {
		if !seen[s] {
			seen[s] = true
			result = append(result, s)
		}
	}
	return result
}

func generateState() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}
