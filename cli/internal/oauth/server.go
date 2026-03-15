package oauth

import (
	"context"
	"fmt"
	"net/http"
	"time"
)

// CallbackURI is the redirect URI used by the callback server.
const CallbackURI = "http://localhost:9876/callback"

// CallbackResult holds the OAuth2 callback parameters.
type CallbackResult struct {
	Code  string
	State string
	Error string
}

// StartCallbackServer starts a temporary HTTP server on port 9876 that waits
// for a single OAuth2 callback, then shuts itself down.
func StartCallbackServer(ctx context.Context) (<-chan CallbackResult, error) {
	resultCh := make(chan CallbackResult, 1)

	mux := http.NewServeMux()
	srv := &http.Server{
		Addr:    fmt.Sprintf(":%d", 9876),
		Handler: mux,
	}

	mux.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
		result := CallbackResult{
			Code:  r.URL.Query().Get("code"),
			State: r.URL.Query().Get("state"),
			Error: r.URL.Query().Get("error"),
		}

		if result.Error != "" {
			fmt.Fprintf(w, "<html><body><h2>Authorization failed: %s</h2><p>You can close this window.</p></body></html>", result.Error)
		} else {
			fmt.Fprintf(w, "<html><body><h2>Authorization successful!</h2><p>You can close this window and return to the terminal.</p></body></html>")
		}

		resultCh <- result

		// Shut down the server after responding
		go func() {
			time.Sleep(100 * time.Millisecond)
			srv.Shutdown(context.Background()) //nolint:errcheck
		}()
	})

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			resultCh <- CallbackResult{Error: err.Error()}
		}
	}()

	// Also shut down if context is cancelled
	go func() {
		<-ctx.Done()
		srv.Shutdown(context.Background()) //nolint:errcheck
	}()

	return resultCh, nil
}
