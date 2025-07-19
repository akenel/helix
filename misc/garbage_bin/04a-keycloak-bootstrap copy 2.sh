#!/bin/bash

# ────────────────────────────────────────────────────────
# 🔐 Keycloak Realm Bootstrap — Sherlock Edition (v2.0)
# Ensures realm, theme, clients, and roles are configured
# ────────────────────────────────────────────────────────

# --- Colors for better output ---
NC='\033[0m' # No Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BRIGHT_GREEN='\033[1;32m'

# --- Configuration Variables ---
REALM="helix"
KC_NAMESPACE="identity"
KC_USER="admin"
KC_PASS="admin" # IMPORTANT: In a real environment, fetch this from a secure source (e.g., Vault)

# --- Flags ---
DEBUG=false
DRYRUN=false
STATUS=false
FORCE_IMPORT=false

# --- Parse Command Line Arguments ---
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --debug) DEBUG=true ;;
    --dry-run) DRYRUN=true ;;
    --status) STATUS=true ;;
    --force-import) FORCE_IMPORT=true ;;
    --help|-h)
      cat <<EOF
🔐 Realm Bootstrap Utility

Usage:
  ./04a-keycloak-bootstrap.sh [--debug] [--dry-run] [--status] [--force-import]

Options:
  --debug         Enable verbose logging
  --dry-run       Simulate changes only (no actual changes made)
  --status        Check if realm '$REALM' exists and exit
  --force-import  Re-import realm from mounted JSON (deletes existing first)
EOF
      exit 0 ;;
    *) echo -e "${RED}❌ Unknown option: $1${NC}"; exit 1 ;;
  esac
  shift
done

# --- Helper Functions ---
log()        { $DEBUG && echo "🪵 DEBUG: $*" >&2; }
announce()   { echo -e "\n${CYAN}🔸 $1${NC}\n" >&2; }
success()    { echo -e "${GREEN}✅ $*${NC}" >&2; }
warn()       { echo -e "${YELLOW}⚠️ $*${NC}" >&2; }
error()      { echo -e "${RED}❌ $*${NC}" >&2; exit 1; }

# --- Locate Keycloak Pod and Determine Internal Host ---
announce "🔍 Locating Keycloak pod and determining internal host..."
KC_POD=$(kubectl get pods -n "$KC_NAMESPACE" -l app.kubernetes.io/name=keycloak -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || true)

if [[ -z "$KC_POD" ]]; then
  error "Could not find Keycloak pod in namespace '$KC_NAMESPACE'. Is Keycloak deployed and running?"
fi
log "Using pod: $KC_POD"

# Dynamically determine the Keycloak service name
# This assumes the Keycloak service has the label app.kubernetes.io/name=keycloak
# and is in the 'identity' namespace.
KC_SERVICE_NAME=$(kubectl get svc -n "$KC_NAMESPACE" -l app.kubernetes.io/name=keycloak -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || true)

if [[ -z "$KC_SERVICE_NAME" ]]; then
    error "Could not find Keycloak service in namespace '$KC_NAMESPACE'. Cannot determine internal host."
fi

# Construct the internal Keycloak service FQDN
# The default HTTP port for Keycloak is 8080
KC_INTERNAL_HOST="${KC_SERVICE_NAME}.${KC_NAMESPACE}.svc.cluster.local:8080"
log "Keycloak internal host: $KC_INTERNAL_HOST"
success "Keycloak pod '$KC_POD' found. Internal host set to '$KC_INTERNAL_HOST'."

# --- Wait for Keycloak API to be responsive ---
announce "⏳ Waiting for Keycloak API to be responsive at ${KC_INTERNAL_HOST}..."
for i in {1..30}; do # Increased timeout attempts for API readiness
  # Use the dynamically determined internal host for the curl check
  if kubectl exec -n "$KC_NAMESPACE" "$KC_POD" -- curl -s "http://localhost:8080/realms/master" >/dev/null 2>&1; then
    success "Keycloak API is responsive."
    break
  fi
  echo "  ⏳ [$i/30] Keycloak API not ready, retrying in 5s..."
  sleep 5
done
if ! kubectl exec -n "$KC_NAMESPACE" "$KC_POD" -- curl -sSf "http://localhost:8080/realms/master"  >/dev/null 2>&1; then
  error "Keycloak API never became ready after 150 seconds. Aborting."
fi

# --- Status Only Mode ---
if $STATUS; then
  announce "📍 Checking if realm '$REALM' exists..."
  # Execute kcadm.sh inside the pod to check realm existence
  # Note: The 'config credentials' command needs the internal host.
  if kubectl exec -n "$KC_NAMESPACE" "$KC_POD" -- bash -c "
    /opt/bitnami/keycloak/bin/kcadm.sh config credentials \
      --server http://localhost:8080/realms/master  --realm master --user ${KC_USER} --password ${KC_PASS} >/dev/null 2>&1 && \
    /opt/bitnami/keycloak/bin/kcadm.sh get realms/${REALM} >/dev/null 2>&1
  "; then
    success "Realm '$REALM' exists."
  else
    warn "Realm '$REALM' not found."
  fi
  exit 0
fi

# --- Dry Run Mode ---
if $DRYRUN; then
  warn "🚫 Dry-run enabled — no changes will be made."
  exit 0
fi

# --- Main Bootstrap Logic (All kcadm.sh commands in one exec session) ---
announce "🚀 Starting Keycloak Realm Bootstrap for '$REALM'..."

# Execute all kcadm.sh commands within a single kubectl exec session.
# This is crucial for kcadm.sh session persistence (credentials).
# Variables from the outer script are expanded here (e.g., $REALM, $KC_INTERNAL_HOST).
# Variables for the inner script need to be escaped (e.g., \$REALM).
kubectl exec -n "$KC_NAMESPACE" "$KC_POD" -- /bin/bash -c "
  set -euo pipefail # Enable strict error checking within the pod's shell

  # Configure kcadm.sh credentials once for this session
  echo -e \"\n${CYAN}  Configuring kcadm.sh credentials...${NC}\"
   /opt/bitnami/keycloak/bin/kcadm.sh config credentials \
    --server http://localhost:8080/realms/master \
    --realm master \
    --user ${KC_USER} \
    --password ${KC_PASS} || { echo -e \"${RED}  ❌ Failed to configure kcadm.sh credentials.${NC}\"; exit 1; }
  echo -e \"${GREEN}  ✅ kcadm.sh credentials configured.${NC}\"

  # --- Realm Import/Update ---
  echo -e \"\n${CYAN}  🌍 Ensuring realm '${REALM}' exists...${NC}\"
  # Ensure JSON_PATH matches the subPath in your Helm values for the ConfigMap mount
  JSON_PATH=\"/opt/keycloak/configs/helix-realm.json\"

  if [[ \"${FORCE_IMPORT}\" == \"true\" ]]; then
    echo -e \"${YELLOW}  🧨 --force-import enabled. Attempting to delete existing realm...${NC}\"
    if /opt/bitnami/keycloak/bin/kcadm.sh get realms/${REALM} >/dev/null 2>&1; then
      /opt/bitnami/keycloak/bin/kcadm.sh delete realms/${REALM} && echo -e \"${GREEN}  ✅ Realm '${REALM}' deleted.${NC}\" || { echo -e \"${RED}  ❌ Failed to delete realm '${REALM}'.${NC}\"; exit 1; }
    else
      echo -e \"${YELLOW}  ℹ️ No existing realm '${REALM}' to delete.${NC}\"
    fi
  fi

  if ! /opt/bitnami/keycloak/bin/kcadm.sh get realms/${REALM} >/dev/null 2>&1; then
    echo -e \"${CYAN}  📦 Importing realm from mounted JSON at ${JSON_PATH}...${NC}\"
    if test -f \"${JSON_PATH}\"; then
      /opt/bitnami/keycloak/bin/kcadm.sh create realms -f \"${JSON_PATH}\" || { echo -e \"${RED}  ❌ Failed to import realm '${REALM}'.${NC}\"; exit 1; }
      echo -e \"${GREEN}  ✅ Realm '${REALM}' successfully imported.${NC}\"
    else
      echo -e \"${RED}  ❌ Realm JSON not found at ${JSON_PATH} inside the pod. Check ConfigMap mount.${NC}\"
      exit 1
    fi
  else
    echo -e \"${YELLOW}  ℹ️ Realm '${REALM}' already exists. Skipping import (use --force-import to re-import).${NC}\"
    # Optional: Uncomment the following block if you always want to update the realm from the JSON
    # echo -e \"${CYAN}  Updating realm '${REALM}' from mounted JSON at ${JSON_PATH}...${NC}\"
    # /opt/bitnami/keycloak/bin/kcadm.sh update realms/${REALM} -f \"${JSON_PATH}\" || { echo -e \"${RED}  ❌ Failed to update realm '${REALM}'.${NC}\"; exit 1; }
    # echo -e \"${GREEN}  ✅ Realm '${REALM}' successfully updated.${NC}\"
  fi

  # --- Theme Verification and Application ---
  echo -e \"\n${CYAN}  🎨 Verifying theme for realm '${REALM}' and applying it...${NC}\"
  THEME_PATH=\"/opt/keycloak/themes/${REALM}\"
  if ! test -f \"\${THEME_PATH}/theme.properties\"; then
    echo -e \"${RED}  ❌ Theme '${REALM}' not mounted correctly at \${THEME_PATH} inside the pod.${NC}\"
    echo -e \"${RED}  💡 Verify ConfigMap, subPath, and volume mount in your Helm values.${NC}\"
    exit 1
  fi
  echo -e \"${GREEN}  ✅ Theme '${REALM}' is mounted.${NC}\"

  echo -e \"${CYAN}  Applying theme '${REALM}' to realm...${NC}\"
  if /opt/bitnami/keycloak/bin/kcadm.sh update realms/${REALM} \
    -s loginTheme=\"${REALM}\" \
    -s accountTheme=\"${REALM}\" \
    -s adminTheme=\"${REALM}\" \
    -s emailTheme=\"${REALM}\"; then
    echo -e \"${GREEN}  ✅ Theme applied successfully.${NC}\"
  else
    echo -e \"${RED}  ❌ Failed to apply theme. Check Keycloak pod logs for details.${NC}\"
    exit 1
  fi

  # --- Client Creation ---
  echo -e \"\n${CYAN}  🔌 Creating standard clients in '${REALM}' realm...${NC}\"
  # IMPORTANT: Adjust redirectUris and other client properties as needed for your applications.
  # For example, if 'portainer.helix' is your ingress URL.
  declare -A clients=(
    [portainer]=\"https://portainer.helix\"
    [kong]=\"https://kong.helix\"
    [adminer]=\"https://adminer.helix\"
    [my-app]=\"http://localhost:3000/*\" # Example for a local development app
    [frontend]=\"https://frontend.helix/callback\"
    [admin]=\"https://admin.helix/callback\"
  )

  for client_id in \"\${!clients[@]}\"; do
    local redirect_uri=\"\${clients[\"\${client_id}\"]}\" # Use \${client_id} for array key access
    if /opt/bitnami/keycloak/bin/kcadm.sh get clients -r \"${REALM}\" --fields clientId | grep -q \"\\\"\${client_id}\\\"\"; then
      echo -e \"${YELLOW}  ℹ️ Client '\${client_id}' already exists. Skipping creation.${NC}\"
    else
      echo -e \"${CYAN}  Creating client '\${client_id}' with redirect URI '\${redirect_uri}'...${NC}\"
      # Note: 'secret' is optional for public clients. For confidential clients, it's needed.
      # This example creates public clients. For confidential, add -s 'bearerOnly=false' -s 'serviceAccountsEnabled=true' etc.
      /opt/bitnami/keycloak/bin/kcadm.sh create clients -r \"${REALM}\" \
        -s clientId=\"\${client_id}\" \
        -s publicClient=true \
        -s 'redirectUris=[\"\${redirect_uri}\"]' \
        -s enabled=true || { echo -e \"${RED}  ❌ Failed to create client '\${client_id}'.${NC}\"; exit 1; }
      echo -e \"${GREEN}  ✅ Client '\${client_id}' created.${NC}\"
    fi
  done

  # --- Role Creation ---
  echo -e \"\n${CYAN}  🔐 Creating standard roles in '${REALM}' realm...${NC}\"
  for role_name in admin viewer editor; do
    if /opt/bitnami/keycloak/bin/kcadm.sh get roles -r \"${REALM}\" --fields name | grep -q \"\\\"\${role_name}\\\"\"; then
      echo -e \"${YELLOW}  ℹ️ Role '\${role_name}' already exists. Skipping creation.${NC}\"
    else
      echo -e \"${CYAN}  Creating role '\${role_name}'...${NC}\"
      /opt/bitnami/keycloak/bin/kcadm.sh create roles -r \"${REALM}\" -s name=\"\${role_name}\" || { echo -e \"${RED}  ❌ Failed to create role '\${role_name}'.${NC}\"; exit 1; }
      echo -e \"${GREEN}  ✅ Role '\${role_name}' created.${NC}\"
    fi
  done

  echo -e \"\n${BRIGHT_GREEN}  🎉 Keycloak Realm Bootstrap for '${REALM}' completed successfully within pod!${NC}\"
" || error "Keycloak post-deployment configuration failed. Please check the logs above for details."

announce "✅ Realm '$REALM' bootstrap complete!"
success "All Keycloak realm configurations applied."
