---
name: ring-ops
description: Use this skill when working on the ring repository to set up providers, run OAuth flows, fetch tokens with the CLI, build/run the macOS menu bar app, and troubleshoot Keychain or scope issues.
---

# Ring Ops Skill

This skill is for contributors and agents working in the `ring` repo.

It covers:
- Building and using the Go CLI (`cli/`)
- Building and running the macOS app (`ring-app/`)
- Typical OAuth and scope workflows
- Practical troubleshooting for Keychain/auth problems

## Repo Structure

- `cli/`: Go binary (`ring`) for scripting and terminal use
- `ring-app/`: SwiftUI menu bar app for setup and scope management
- Shared Keychain service: `com.ring.tokenstore`

## Quick Start

### Build CLI

```bash
cd /Users/jordi/projects/ring/cli
go build -o dist/ring ./cmd
./dist/ring --help
```

### Build and Run App

```bash
cd /Users/jordi/projects/ring/ring-app
xcodegen generate
xcodebuild -scheme Ring -configuration Debug \
  -derivedDataPath /tmp/ring-derived \
  build
open /tmp/ring-derived/Build/Products/Debug/Ring.app
```

## Common Workflows

### 1) Configure + Login a provider from CLI

```bash
cd /Users/jordi/projects/ring/cli
./dist/ring setup google
./dist/ring login google
./dist/ring token google
```

### 2) Validate provider state

```bash
./dist/ring list
./dist/ring status google
```

### 3) Work with scopes

```bash
./dist/ring scopes google
./dist/ring scopes google --add https://www.googleapis.com/auth/gmail.readonly
./dist/ring token google --require-scope https://www.googleapis.com/auth/gmail.readonly
```

### 4) Use token in API calls

```bash
TOKEN="$(./dist/ring token github)"
curl -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
  https://api.github.com/user
```

## Menu Bar App Flow

1. Open `ring` from the menu bar icon.
2. Select a provider and use `Login` / `Setup`.
3. Use `Scopes` to select additional scopes and re-authorize.
4. Return to CLI to consume tokens in scripts.

## Troubleshooting

### CLI says provider is not configured

- Confirm same machine/user profile is being used.
- Check app and CLI both target `com.ring.tokenstore`.
- Re-run `ring setup <provider>` and `ring login <provider>`.

### GitHub browser flow does not start

- Verify provider config uses authorization endpoint (not device code endpoint).
- Verify callback URL in GitHub OAuth App matches app configuration exactly.

### Build succeeds but app behaves old

- Restart app process and reopen built app from `/tmp/ring-derived/.../Ring.app`.
- Clear stale launch instances before testing.

## Guardrails

- Do not print full access tokens in logs or PR descriptions.
- Prefer minimal scopes needed for a task.
- Keep Keychain data local; avoid exporting secrets unless explicitly requested.

## When to Use This Skill

Use this skill whenever the task mentions:
- `ring` CLI commands (`setup`, `login`, `token`, `scopes`, `status`)
- OAuth provider onboarding in this repo
- Menu bar app setup/scope UI behavior
- Token retrieval for validating API calls
