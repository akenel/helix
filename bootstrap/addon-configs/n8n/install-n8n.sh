#!/usr/bin/env bash

set -euo pipefail

PLUGIN_CHART="oci://8gears.container-registry.com/library/n8n"
PLUGIN_NAME="n8n"
PLUGIN_VESION="1.0.10" 
REPO2ADD="8gears"
REPO_HOOK="oci://8gears.container-registry.com"
PLUGIN_DESC="n8n: Low-code workflow automation"
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
HELIX_ROOT="$(realpath "${SCRIPT_DIR}/../..")"
VALUES_FILE="${HELIX_ROOT}/addon-configs/${PLUGIN_NAME}/${PLUGIN_NAME}-values.yaml"

echo "☕ Installing plugin 🥐 $PLUGIN_NAME — $PLUGIN_DESC"
echo "🔸 Script Path: $SCRIPT_PATH"
echo "🔸 Root Dir   : $HELIX_ROOT"
echo "🔸 Values File: $VALUES_FILE"
echo ""

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "❌ Missing values file: $VALUES_FILE"
  exit 1
fi

helm repo add $REPO2ADD $REPO_HOOK || true
helm repo update

helm upgrade --install $PLUGIN_NAME $PLUGIN_CHART \
  --version $PLUGIN_VESION \
  --namespace $PLUGIN_NAME --create-namespace \
  -f $VALUES_FILE \
  --debug --atomic || {
    echo "❌ Deployment failed for $PLUGIN_NAME"
    exit 1
  }

echo "✅ $PLUGIN_NAME installed!"
echo "🌐 Access at: https://$PLUGIN_NAME.helix"
