#!/usr/bin/env bash
# utils/core/config.sh - Load config for any service dynamically.
set -euo pipefail

# Expects SCRIPT_DIR to be exported from the calling script
# Example:
# export SCRIPT_DIR="/home/angel/helix_v3/bootstrap"

# Constants
LOGO="🔐"
SUCCESS="✅"
INFO="ℹ️"
ERROR="❌"

# Function: Load service configuration from hardcoded logic
load_env_for_service() {
  local service_name="$1"

  # Reset all known config vars
  NAMESPACE=""
  DISPLAY=""
  HELM_REPO_NAME=""
  HELM_REPO_URL=""
  INGRESS_HOST=""
  AUTH="false"
  SECRET_SCRIPT=""
  HELM_EXTRA_ARGS=""

  case "$service_name" in
    "portainer")
      NAMESPACE="portainer"
      DISPLAY="🧱 Portainer (Docker UI)"
      HELM_REPO_NAME="portainer"
      HELM_REPO_URL="https://portainer.github.io/k8s/"
      INGRESS_HOST="portainer.helix"
      AUTH="true"
      SECRET_SCRIPT="${SCRIPT_DIR}/configs/${service_name}/secrets/${service_name}-secrets.sh"
      ;;

    "vault")
      NAMESPACE="vault"
      DISPLAY="🔐 Vault (Secrets)"
      HELM_REPO_NAME="hashicorp"
      HELM_REPO_URL="https://helm.releases.hashicorp.com"
      INGRESS_HOST="vault.helix"
      AUTH="true"
      ;;

    *)
      echo "$ERROR Unknown service: $service_name"
      exit 1
      ;;
  esac

  echo "$INFO Loaded config for $service_name"
  echo "     Namespace: $NAMESPACE"
  echo "     Ingress:   $INGRESS_HOST"
  echo "     Auth:      $AUTH"
  echo "     Secrets:   ${SECRET_SCRIPT:-None}"
}

# Function: Source the .env file for the service
load_env_file() {
  local service_name="$1"
  local env_file="${SCRIPT_DIR}/configs/${service_name}/${service_name}.env"

  if [[ -f "$env_file" ]]; then
    set -a
    source "$env_file"
    set +a
    echo "$INFO Loaded environment file: $env_file"
  else
    echo "$ERROR Missing environment file: $env_file"
    exit 1
  fi
}

# Function: Run the service's secret generation script, if defined
run_secret_script() {
  echo "$INFO DEBUG: SECRET_SCRIPT='$SECRET_SCRIPT'"
  echo "$INFO DEBUG: Does it exist? $(if [[ -f "$SECRET_SCRIPT" ]]; then echo yes; else echo no; fi)"
  echo "$INFO DEBUG: Is it executable? $(if [[ -x "$SECRET_SCRIPT" ]]; then echo yes; else echo no; fi)"

  if [[ -n "$SECRET_SCRIPT" && -x "$SECRET_SCRIPT" ]]; then
    echo "$LOGO Running secret script for $SERVICE..."
    bash "$SECRET_SCRIPT"
  elif [[ -n "$SECRET_SCRIPT" ]]; then
    echo "$ERROR Secret script defined but not executable: $SECRET_SCRIPT"
    exit 1
  else
    echo "$INFO No secrets to configure for $SERVICE"
  fi
}

# Function: Register OIDC client using env vars from service
register_oidc_client() {
  local host="${OIDC_ISSUER%/realms/*}"
  local realm="${OIDC_ISSUER##*/realms/}"

  local token
  token=$(curl -s -X POST "$host/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin" -d "password=admin" \
    -d "grant_type=password" -d "client_id=admin-cli" | jq -r .access_token)

  curl -s -X POST "$host/admin/realms/$realm/clients" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{
      \"clientId\": \"$OIDC_CLIENT_ID\",
      \"enabled\": true,
      \"redirectUris\": [\"https://$INGRESS_HOST/*\"],
      \"protocol\": \"openid-connect\",
      \"publicClient\": false,
      \"standardFlowEnabled\": true
    }" || echo "⚠️ Possibly already exists, continuing..."
}

# Function: Call everything together for a given service
bootstrap_service_config() {
  local svc="$1"
  export SERVICE="$svc"

  load_env_for_service "$svc"
  load_env_file "$svc"
  run_secret_script

  if [[ "$AUTH" == "true" ]]; then
    configure_oidc_for_service
  fi
}

# Function: Configure OIDC (called only if AUTH is true)
configure_oidc_for_service() {
  echo "$LOGO Configuring OIDC for $DISPLAY..."

  local token
  token=$(curl -s -X POST "https://keycloak.helix/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin" -d "password=admin" \
    -d "grant_type=password" -d "client_id=admin-cli" | jq -r .access_token)

  curl -s -X POST "https://keycloak.helix/admin/realms/helix/clients" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{
      \"clientId\": \"$OIDC_CLIENT_ID\",
      \"enabled\": $AUTH,
      \"redirectUris\": [\"https://$INGRESS_HOST/*\"],
      \"protocol\": \"openid-connect\",
      \"publicClient\": false,
      \"standardFlowEnabled\": true
    }" || echo "⚠️ Might already exist, no harm"

  echo "$SUCCESS OIDC setup complete for $SERVICE"
}
