#!/usr/bin/env bash
# utils/vault-healthcheck.sh — Sherlock's Vault diagnostic tool

set -euo pipefail

LOGO="🔍"
SUCCESS="✅"
FAIL="❌"
INFO="ℹ️"

VAULT_ADDR="${VAULT_ADDR:-http://vault.helix:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

echo "$LOGO Vault Address: $VAULT_ADDR"

# 1. 🧠 Check DNS
echo -n "$INFO Resolving host... "
vault_host=$(echo "$VAULT_ADDR" | awk -F[/:] '{print $4}')
if getent hosts "$vault_host" > /dev/null; then
  echo "$SUCCESS Host resolves: $vault_host"
else
  echo "$FAIL Hostname does not resolve: $vault_host"
  exit 1
fi

# 2. 🔌 Check network connectivity
echo -n "$INFO Connecting to Vault... "
if curl -s --connect-timeout 2 "$VAULT_ADDR/v1/sys/health" >/dev/null; then
  echo "$SUCCESS Vault is reachable"
else
  echo "$FAIL Cannot connect to Vault at $VAULT_ADDR"
  exit 1
fi

# 3. 🏥 Check Vault health
echo "$INFO Checking Vault status..."
health=$(curl -s "$VAULT_ADDR/v1/sys/health")
initialized=$(echo "$health" | jq -r .initialized)
sealed=$(echo "$health" | jq -r .sealed)

if [[ "$initialized" == "true" && "$sealed" == "false" ]]; then
  echo "$SUCCESS Vault is initialized and unsealed"
else
  echo "$FAIL Vault is either uninitialized or sealed"
  echo "$INFO initialized: $initialized, sealed: $sealed"
  exit 1
fi

# 4. 🪪 Validate token (if set)
if [[ -n "$VAULT_TOKEN" ]]; then
  echo "$INFO Validating VAULT_TOKEN..."
  if vault token lookup &>/dev/null; then
    echo "$SUCCESS Token is valid"
  else
    echo "$FAIL Token is invalid or expired"
    exit 1
  fi
else
  echo "$INFO No VAULT_TOKEN provided, skipping token check"
fi

echo "$SUCCESS Vault is healthy and ready!"
