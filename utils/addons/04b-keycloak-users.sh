#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🔐 04b - Keycloak User Bootstrap
# 📜 Adds default users + role mappings to 'helix' realm
# 🧠 helix_v3/utils/bootstrap/04b-keycloak-users.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

set -euo pipefail

REALM="helix"
KC_NAMESPACE="identity"
KC_USER="admin"
KC_PASS="admin"
KC_HOST="http://localhost:8080"

DEBUG=false
DRYRUN=false
HELP=false
STATUS=false

USERS=(
  "guest:guest:public"
  "dev:dev:developer"
  "tester:tester:viewer"
)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🚩 Parse Flags
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --help|-h) HELP=true ;;
    --debug) DEBUG=true ;;
    --dry-run) DRYRUN=true ;;
    --status) STATUS=true ;;
    *) echo "❌ Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🪵 Debug & Announce Helpers
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
log()     { $DEBUG && echo "🪵 DEBUG: $*" >&2; }
announce() { echo -e "\n🔸 $1\n" >&2; }

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📖 Help Menu
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if $HELP; then
cat <<EOF
🔐 Keycloak User Bootstrap

Usage:
  ./04b-keycloak-users.sh [options]

Options:
  --help         Show help menu
  --debug        Enable verbose logging
  --dry-run      Simulate user creation
  --status       Only show existing users
EOF
exit 0
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🔍 Locate Keycloak Pod
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
KC_POD=$(kubectl get pods -n "$KC_NAMESPACE" -l "app.kubernetes.io/name=keycloak" --no-headers 2>/dev/null | awk 'NR==1{print $1}')
if [[ -z "$KC_POD" ]]; then
  echo "❌ Could not find a running Keycloak pod in namespace '$KC_NAMESPACE'." >&2
  exit 1
fi

log "Using Keycloak pod: $KC_POD"

# 🛠 Prepare kcadm.sh wrapper
KC_KCADM_BIN_PATH="/opt/bitnami/keycloak/bin/kcadm.sh"
KC_TEMP_CONFIG_FILE="/tmp/kcadm_bootstrap_config.json"

KCADM=(kubectl exec -n "$KC_NAMESPACE" "$KC_POD" -- bash -c \
  "rm -f '$KC_TEMP_CONFIG_FILE'; $KC_KCADM_BIN_PATH \"\$@\" --config $KC_TEMP_CONFIG_FILE" --)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🔐 Authenticate to Target Realm
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
announce "Authenticating to Keycloak CLI (realm: $REALM)..."
"${KCADM[@]}" config credentials \
  --server "$KC_HOST" \
  --realm "$REALM" \
  --user "$KC_USER" \
  --password "$KC_PASS" >/dev/null

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🔎 STATUS CHECK ONLY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if $STATUS; then
  announce "🔎 Checking user existence in realm '$REALM'..."
  for entry in "${USERS[@]}"; do
    IFS=":" read -r uname _ _ <<< "$entry"
    echo -n "🔍 User '$uname': "
    if "${KCADM[@]}" get users -r "$REALM" --query username="$uname" &>/dev/null; then
      echo "✅ Found"
    else
      echo "❌ Missing"
    fi
  done
  exit 0
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🧪 DRY-RUN Mode
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if $DRYRUN; then
  announce "🧪 Dry-run mode enabled. No users will be created."
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 👤 Create Users and Assign Roles
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
announce "👤 Creating users and assigning roles in realm '$REALM'..."

for entry in "${USERS[@]}"; do
  IFS=":" read -r uname upass urole <<< "$entry"
  log "Processing user: $uname (role: $urole)"

  if $DRYRUN; then
    echo "🔬 Would create user '$uname' with role '$urole'" >&2
    continue
  fi

  # Attempt to create the user
  if "${KCADM[@]}" create users -r "$REALM" \
      -s username="$uname" \
      -s enabled=true \
      -s emailVerified=true \
      -s credentials="[{'type':'password','value':'$upass','temporary':false}]" \
      &>/dev/null; then
    echo "✅ User '$uname' created." >&2
  else
    echo "⚠️  User '$uname' may already exist or failed to create." >&2
  fi

  # Retrieve user ID
  USER_ID=$("${KCADM[@]}" get users -r "$REALM" --query username="$uname" --fields id --format csv 2>/dev/null | tail -n 1)

  if [[ -n "$USER_ID" ]]; then
    log "Found user ID: $USER_ID"
    if "${KCADM[@]}" add-roles -r "$REALM" --uusername "$uname" --rolename "$urole" &>/dev/null; then
      echo "✅ Assigned role '$urole' to user '$uname'" >&2
    else
      echo "⚠️  Could not assign role '$urole' to user '$uname'" >&2
    fi
  else
    echo "❌ Failed to retrieve user ID for '$uname'" >&2
  fi
done

announce "🎉 User provisioning complete in realm '$REALM'"
exit 0
