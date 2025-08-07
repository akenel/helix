#!/usr/bin/env bash
set -euo pipefail

export KEYCLOAK_URL="http://keycloak.${CLUSTER}/auth"
export REALM_NAME="helix"
export ADMIN_USER="admin"
export ADMIN_PASS="admin"

echo "🔑 Getting admin access token..."
ACCESS_TOKEN=$(curl -s \
  -d "username=${ADMIN_USER}" \
  -d "password=${ADMIN_PASS}" \
  -d 'grant_type=password' \
  -d 'client_id=admin-cli' \
  "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" | jq -r .access_token)

[[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]] && {
  echo "❌ Failed to get access token."
  exit 1
}

upload() {
  local FILE=$1
  local ENDPOINT=$2

  echo "📤 Uploading $FILE to $ENDPOINT"
  curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/${ENDPOINT}" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d @"$FILE"
  echo ""
}

# Example imports
upload parts/roles.json roles
upload parts/users.json users
upload parts/groups.json groups
upload parts/client-scopes.json client-scopes

for CLIENT_FILE in parts/clients/*.json; do
  upload "$CLIENT_FILE" clients
done
