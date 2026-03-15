package totp

import (
	"fmt"
	"time"

	"github.com/pquerna/otp/totp"
)

// Generate produces a 6-digit TOTP code from a base32-encoded secret.
func Generate(secret string) (string, error) {
	code, err := totp.GenerateCode(secret, time.Now())
	if err != nil {
		return "", fmt.Errorf("failed to generate TOTP code: %w", err)
	}
	return code, nil
}
