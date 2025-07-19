#!/bin/bash

# ┌────────────────────────────────────────────────┐
# │ 🔧 Keycloak ConfigMap Creation Helper          │
# │ 📂 Uses: themes/helix, realms/helix-realm.json │
# └────────────────────────────────────────────────┘
# ┌────────────────────────────────────────────┐
# │ 🔧 Keycloak ConfigMap Creation Utility     │
# │ Supports: --debug, --test                  │
# └────────────────────────────────────────────┘

set -euo pipefail

# 🧠 Default Configuration
REALM="helix"
THEME_CONFIGMAP="helix-theme"
REALM_CONFIGMAP="helix-realm-import"
DEBUG=false
TEST=false

# 🔍 Required ENV: Set by the caller
: "${HELIX_KEYCLOAK_CONFIGS_DIR:?Missing HELIX_KEYCLOAK_CONFIGS_DIR}"
: "${NAMESPACE:?Missing NAMESPACE}"

# 🗂️ Derived paths
THEME_SOURCE_DIR="${HELIX_KEYCLOAK_CONFIGS_DIR}/themes/${REALM}"
REALM_JSON="${HELIX_KEYCLOAK_CONFIGS_DIR}/realms/${REALM}-realm.json"

# 🎛️ Flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) DEBUG=true ;;
    --test) TEST=true ;;
    --help|-h)
      cat <<EOF
🔧 Keycloak ConfigMap Creation Helper

Usage:
  source ./utils/create-keycloak-configmaps.sh [--debug] [--test]

Flags:
  --debug     Verbose output
  --test      Dry-run mode (does not apply)
EOF
      return 0 ;;
    *) echo "❌ Unknown flag: $1" >&2; return 1 ;;
  esac
  shift
done

log() { $DEBUG && echo "🪵 DEBUG: $*" >&2; }

# ───────────────────────────────────────────────
# 🧩 1. Theme ConfigMap
# ───────────────────────────────────────────────
echo "🎨 Creating theme ConfigMap: $THEME_CONFIGMAP"
log "Theme source directory: $THEME_SOURCE_DIR"

if [[ -d "$THEME_SOURCE_DIR" && -n "$(ls -A "$THEME_SOURCE_DIR")" ]]; then
  if $TEST; then
    echo "🧪 [TEST] Would create ConfigMap '$THEME_CONFIGMAP' from $THEME_SOURCE_DIR"
    kubectl create configmap "$THEME_CONFIGMAP" \
      --from-file="$THEME_SOURCE_DIR" \
      -n "$NAMESPACE" --dry-run=client -o yaml
  else
    kubectl create configmap "$THEME_CONFIGMAP" \
      --from-file="$THEME_SOURCE_DIR" \
      -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    echo "✅ Created ConfigMap: $THEME_CONFIGMAP"
  fi
else
  echo "❌ Theme directory missing or empty: $THEME_SOURCE_DIR" >&2
  return 1
fi

# ───────────────────────────────────────────────
# 📦 2. Realm JSON ConfigMap
# ───────────────────────────────────────────────
echo "🗂️ Creating realm ConfigMap: $REALM_CONFIGMAP"
log "Realm JSON path: $REALM_JSON"

if [[ -f "$REALM_JSON" ]]; then
  if $TEST; then
    echo "🧪 [TEST] Would create ConfigMap '$REALM_CONFIGMAP' from $REALM_JSON"
    kubectl create configmap "$REALM_CONFIGMAP" \
      --from-file="helix-realm.json=$REALM_JSON" \
      -n "$NAMESPACE" --dry-run=client -o yaml
  else
    kubectl create configmap "$REALM_CONFIGMAP" \
      --from-file="helix-realm.json=$REALM_JSON" \
      -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    echo "✅ Created ConfigMap: $REALM_CONFIGMAP"
  fi
else
  echo "❌ Realm JSON file not found: $REALM_JSON" >&2
  return 1
fi

echo "🔐 Keycloak ConfigMap creation complete."
