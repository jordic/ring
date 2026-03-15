package token

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/jordic/ring/internal/keychain"
	"github.com/jordic/ring/internal/providers"
)

const proactiveRefreshWindow = 5 * time.Minute

// TokenData holds the raw keychain data for a provider's OAuth2 token.
type TokenData struct {
	AccessToken  string
	RefreshToken string
	ExpiresAt    *time.Time
	Scopes       []string
}

// Load reads token data from the keychain for the given provider.
func Load(providerID string) (*TokenData, error) {
	at, err := keychain.Get(providerID + ".access_token")
	if err != nil {
		return nil, providers.ErrNotLoggedIn
	}

	td := &TokenData{AccessToken: at}

	if rt := keychain.Get2(providerID + ".refresh_token"); rt != "" {
		td.RefreshToken = rt
	}

	if expiresStr := keychain.Get2(providerID + ".expires_at"); expiresStr != "" {
		t, err := time.Parse(time.RFC3339, expiresStr)
		if err == nil {
			td.ExpiresAt = &t
		}
	}

	if scopesStr := keychain.Get2(providerID + ".scopes"); scopesStr != "" {
		td.Scopes = strings.Split(scopesStr, ",")
	}

	return td, nil
}

// Save writes token data back to the keychain.
func Save(providerID string, td *TokenData) error {
	if err := keychain.Set(providerID+".access_token", td.AccessToken); err != nil {
		return err
	}

	if td.RefreshToken != "" {
		if err := keychain.Set(providerID+".refresh_token", td.RefreshToken); err != nil {
			return err
		}
	}

	if td.ExpiresAt != nil {
		if err := keychain.Set(providerID+".expires_at", td.ExpiresAt.Format(time.RFC3339)); err != nil {
			return err
		}
	}

	if len(td.Scopes) > 0 {
		if err := keychain.Set(providerID+".scopes", strings.Join(td.Scopes, ",")); err != nil {
			return err
		}
	}

	return nil
}

// NeedsRefresh checks whether the token needs refreshing based on the strategy.
func NeedsRefresh(td *TokenData, strategy providers.RefreshStrategy) bool {
	if strategy == providers.RefreshNever {
		return false
	}
	if td.ExpiresAt == nil {
		return false
	}
	switch strategy {
	case providers.RefreshProactive:
		return time.Now().Add(proactiveRefreshWindow).After(*td.ExpiresAt)
	case providers.RefreshOnExpiry:
		return time.Now().After(*td.ExpiresAt)
	}
	return false
}

// refreshTokenResponse is the standard OAuth2 token refresh response.
type refreshTokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
	TokenType    string `json:"token_type"`
	Error        string `json:"error"`
	ErrorDesc    string `json:"error_description"`
}

// Refresh calls the provider's token endpoint to get a new access token.
func Refresh(p providers.Provider, td *TokenData, clientID, clientSecret string) (*TokenData, error) {
	if td.RefreshToken == "" {
		return nil, fmt.Errorf("%w: no refresh token stored", providers.ErrRefreshFailed)
	}

	data := url.Values{}
	data.Set("grant_type", "refresh_token")
	data.Set("refresh_token", td.RefreshToken)
	data.Set("client_id", clientID)
	if clientSecret != "" {
		data.Set("client_secret", clientSecret)
	}

	req, err := http.NewRequestWithContext(context.Background(), "POST", p.TokenURL, strings.NewReader(data.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", providers.ErrRefreshFailed, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var tr refreshTokenResponse
	if err := json.Unmarshal(body, &tr); err != nil {
		return nil, fmt.Errorf("failed to parse refresh response: %w", err)
	}

	if tr.Error != "" {
		return nil, fmt.Errorf("%w: %s", providers.ErrRefreshFailed, tr.ErrorDesc)
	}

	newTD := &TokenData{
		AccessToken:  tr.AccessToken,
		RefreshToken: td.RefreshToken, // keep old refresh token if not rotated
		Scopes:       td.Scopes,
	}
	if tr.RefreshToken != "" {
		newTD.RefreshToken = tr.RefreshToken
	}
	if tr.ExpiresIn > 0 {
		t := time.Now().Add(time.Duration(tr.ExpiresIn) * time.Second)
		newTD.ExpiresAt = &t
	}

	return newTD, nil
}

// Exchange calls the token endpoint with the given form values and returns a TokenData.
func Exchange(tokenURL, clientID, clientSecret string, data url.Values) (*TokenData, error) {
	req, err := http.NewRequestWithContext(context.Background(), "POST", tokenURL, strings.NewReader(data.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("token exchange failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var tr refreshTokenResponse
	if err := json.Unmarshal(body, &tr); err != nil {
		return nil, fmt.Errorf("failed to parse token response: %w", err)
	}

	if tr.Error != "" {
		return nil, fmt.Errorf("%w: %s — %s", providers.ErrInvalidClient, tr.Error, tr.ErrorDesc)
	}

	td := &TokenData{
		AccessToken:  tr.AccessToken,
		RefreshToken: tr.RefreshToken,
	}
	if tr.ExpiresIn > 0 {
		t := time.Now().Add(time.Duration(tr.ExpiresIn) * time.Second)
		td.ExpiresAt = &t
	}
	return td, nil
}

// GetOrRefresh loads a token and refreshes it if needed, persisting the result.
func GetOrRefresh(p providers.Provider) (*TokenData, error) {
	td, err := Load(p.ID)
	if err != nil {
		return nil, err
	}

	if !NeedsRefresh(td, p.RefreshStrategy) {
		return td, nil
	}

	clientID, err := keychain.Get(p.ID + ".client_id")
	if err != nil {
		return nil, providers.ErrNotConfigured
	}

	clientSecret := keychain.Get2(p.ID + ".client_secret")

	newTD, err := Refresh(p, td, clientID, clientSecret)
	if err != nil {
		return nil, err
	}

	if err := Save(p.ID, newTD); err != nil {
		return nil, fmt.Errorf("failed to save refreshed token: %w", err)
	}

	return newTD, nil
}
