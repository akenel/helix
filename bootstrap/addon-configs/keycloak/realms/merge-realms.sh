#!/bin/bash
set -euo pipefail

echo "🔧 Merging Keycloak realm fragments into helix-realm-full.json..."

# Merge client JSON files into an array
CLIENTS=$(jq -s '.' parts/clients/*.json)

# Compose final JSON using jq directly
jq -n \
  --slurpfile realm parts/realm_base.json \
  --slurpfile clientScopes parts/client-scopes.json \
  --slurpfile groups parts/groups.json \
  --slurpfile roles parts/roles.json \
  --slurpfile users parts/users.json \
  --argjson clients "$CLIENTS" \
  '
  $realm[0] + {
    clients: $clients,
    clientScopes: $clientScopes[0],
    groups: $groups[0],
    roles: $roles[0],
    users: $users[0]
  }
  ' > helix-realm-full.json

echo "✅ Done: helix-realm-full.json has been created successfully."
