#!/bin/bash
set -x # Add this line for verbose debugging
set -euo pipefail

# ... rest of your script ...
# Configuration variables
REALM="helix"
KC_NAMESPACE="identity" # Keycloak namespace
KC_USER="admin"
KC_PASS="admin"
KC_HOST="http://localhost:8080" # Keycloak internal host within the cluster
VAULT_PATH="secret/helix/identity/clients"
CLIENTS=( "portainer" "kong" "adminer" )

# Vault environment variables (will be sourced from file)
# These will be used for 'kubectl exec' commands into the Vault pod
VAULT_NAMESPACE="vault" # Vault's namespace in Kubernetes
VAULT_RELEASE="vault-helix" # Vault's Helm release name (from 00_vault-bootstrap.sh)

# Debugging and operational flags
DEBUG=false
DRYRUN=false
HELP=false
STATUS=false

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Parse Flags
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --help|-h) HELP=true ;;
    --debug) DEBUG=true ;;
    --dry-run) DRYRUN=true ;;
    --status) STATUS=true ;;
    *) echo "❌ Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Logging Functions
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
log() {
  $DEBUG && echo "🪵 DEBUG: $*" >&2 || :
}

announce() {
  echo -e "\n🔸 $1\n" >&2
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Help Menu
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if ${HELP:-false}; then
  cat <<EOF
🔐 Keycloak → Vault Client Secret Sync

Usage:
  ./04c-keycloak-client-secrets.sh [options]

Options:
  --help         Show this help menu
  --debug        Enable debug output
  --dry-run      Show secrets without pushing to Vault
  --status       Display current secrets in Vault at $VAULT_PATH
EOF
  exit 0
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Load Vault Environment Variables
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
announce "Loading Vault environment variables..."
VAULT_ENV_FILE="./configs/vault/vault.env"
VAULT_ROOT_TOKEN_FILE="./configs/vault/.vault_root_token" # This might be root, or an admin token

if [ -f "$VAULT_ENV_FILE" ]; then
  set -a # Automatically export all variables after this point
  source "$VAULT_ENV_FILE"
  set +a # Stop auto-exporting
else
  echo "❌ Vault environment file missing: $VAULT_ENV_FILE. Please run Vault bootstrap script first." >&2
  exit 1
fi

if [ -f "$VAULT_ROOT_TOKEN_FILE" ]; then
  VAULT_ROOT_TOKEN=$(<"$VAULT_ROOT_TOKEN_FILE")
else
  echo "❌ Vault root/admin token file missing: $VAULT_ROOT_TOKEN_FILE. Please run Vault bootstrap script first." >&2
  exit 1
fi

# Check if essential Vault variables are loaded
if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ] || \
   [ -z "${VAULT_NAMESPACE:-}" ] || [ -z "${VAULT_RELEASE:-}" ] || \
   [ -z "${VAULT_ROOT_TOKEN:-}" ]; then
  echo "❌ Missing essential VAULT_* variables after sourcing $VAULT_ENV_FILE. Check its content." >&2
  exit 1
fi

log "Vault config loaded: VAULT_ADDR=$VAULT_ADDR, VAULT_NAMESPACE=$VAULT_NAMESPACE, VAULT_RELEASE=$VAULT_RELEASE"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Locate Vault Pod
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
announce "Locating Vault pod..."
VAULT_POD_NAME=$(kubectl get pods -n "$VAULT_NAMESPACE" -l \
  app.kubernetes.io/instance="$VAULT_RELEASE",app.kubernetes.io/name=vault \
  --no-headers -o custom-columns=":metadata.name" | head -n 1)

if [[ -z "$VAULT_POD_NAME" ]]; then
  echo "❌ Vault pod not found in namespace '$VAULT_NAMESPACE' with release '$VAULT_RELEASE'." >&2
  echo "Please ensure Vault is deployed and running via your bootstrap script." >&2
  exit 1
fi
log "Using Vault pod: $VAULT_POD_NAME"
echo "✅ Vault pod found: $VAULT_POD_NAME" >&2


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Vault Status Check (from inside the pod)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
announce "Checking Vault status (from inside the pod)..."
VAULT_STATUS_JSON=$(kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD_NAME" -- \
  sh -c "VAULT_ADDR='$VAULT_ADDR' VAULT_TOKEN='$VAULT_ROOT_TOKEN' vault status -format=json" 2>/dev/null || echo "")

if [ -z "$VAULT_STATUS_JSON" ] || ! echo "$VAULT_STATUS_JSON" | jq -e '.' >/dev/null 2>&1; then
  echo "❌ Failed to get Vault status or invalid JSON response. Is Vault unsealed?" >&2
  exit 1
fi

IS_SEALED=$(jq -r '.sealed' <<< "$VAULT_STATUS_JSON")

if [[ "$IS_SEALED" == "true" ]]; then
  echo "❌ Vault is sealed. Please unseal Vault using your bootstrap script or manually." >&2
  exit 1
else
  echo "✅ Vault is unsealed and ready for operations." >&2
fi


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Status Check Mode (using kubectl exec for vault kv get)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if $STATUS; then
  announce "🔍 Existing client secrets in Vault at '$VAULT_PATH'"
  # Execute vault kv get inside the Vault pod
  kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD_NAME" -- \
    sh -c "VAULT_ADDR='$VAULT_ADDR' VAULT_TOKEN='$VAULT_TOKEN' vault kv get -field=data \"$VAULT_PATH\"" 2>&1 \
    || echo "⚠️ No secrets found or error retrieving secrets from Vault." >&2
  exit 0
fi


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Locate Keycloak Pod
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
announce "Locating Keycloak pod..."
KC_POD=$(kubectl get pods -n "$KC_NAMESPACE" -l "app.kubernetes.io/name=keycloak" --no-headers 2>/dev/null | awk 'NR==1{print $1}')
if [[ -z "$KC_POD" ]]; then
  KC_POD=$(kubectl get pods -n "$KC_NAMESPACE" --no-headers | awk '/keycloak/ {print $1; exit}')
fi

if [[ -z "$KC_POD" ]]; then
  echo "❌ Keycloak pod not found in namespace '$KC_NAMESPACE'." >&2
  exit 1
fi
log "Using Keycloak pod: $KC_POD"
echo "✅ Keycloak pod found: $KC_POD" >&2

# 🛠 Use temporary config path for kcadm.sh inside the pod
KC_KCADM_BIN_PATH="/opt/bitnami/keycloak/bin/kcadm.sh"
KC_TEMP_CONFIG_FILE="/tmp/kcadm_bootstrap_config.json"

# KCADM array definition for kubectl exec:
KCADM=(
  kubectl exec -n "$KC_NAMESPACE" "$KC_POD"
  -- bash -c "rm -f ${KC_TEMP_CONFIG_FILE} && ${KC_KCADM_BIN_PATH} \"\$@\" --config ${KC_TEMP_CONFIG_FILE}" --
)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Authenticate to Keycloak
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
announce "Authenticating to Keycloak CLI (inside Keycloak pod)..."
"${KCADM[@]}" config credentials --server "$KC_HOST" --realm master \
  --user "$KC_USER" --password "$KC_PASS" >/dev/null \
  || { echo "❌ Failed to authenticate to Keycloak CLI. Check credentials or Keycloak status." >&2; exit 1; }
echo "✅ Authenticated to Keycloak CLI." >&2

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Fetch & Store Client Secrets
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
declare -A SECRET_MAP

announce "🔐 Extracting client secrets from Keycloak..."

for client in "${CLIENTS[@]}"; do
  log "Fetching secret for client: $client"
  SECRET=$("${KCADM[@]}" get clients -r "$REALM" --fields clientId,secret --format json 2>/dev/null \
    | jq -r ".[] | select(.clientId == \"$client\") | .secret")

  if [[ -z "$SECRET" || "$SECRET" == "null" ]]; then
    echo "⚠️ Secret not found for client '$client' or client does not exist." >&2
    continue
  fi

  echo "✅ Client '$client' secret extracted." >&2 # Log successful extraction
  SECRET_MAP["$client"]="$SECRET"
done

if $DRYRUN; then
  announce "🚫 Dry-run mode enabled. Secrets NOT pushed to Vault."
  for c in "${!SECRET_MAP[@]}"; do
    echo "🔐 Would write: $VAULT_PATH/${c} → ${SECRET_MAP[$c]}" >&2
  done
  exit 0
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Push secrets to Vault (as a single KV)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
announce "📦 Writing all client secrets to Vault at: $VAULT_PATH"
# Build the key-value pairs for vault kv put dynamically
VAULT_KV_ARGS=()
for c in "${!SECRET_MAP[@]}"; do
  VAULT_KV_ARGS+=( "${c}=${SECRET_MAP[$c]}" )
done

# Execute vault kv put inside the Vault pod
kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD_NAME" -- \
  sh -c "VAULT_ADDR='$VAULT_ADDR' VAULT_TOKEN='$VAULT_TOKEN' \
  vault kv put \"$VAULT_PATH\" ${VAULT_KV_ARGS[*]}" >/dev/null \
  && echo "✅ Secrets successfully written to Vault." >&2 \
  || { echo "❌ Failed to write secrets to Vault." >&2; exit 1; }

exit 0