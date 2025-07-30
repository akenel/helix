#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR

# 🧱 HELIX Service Deployment Script
# Purpose: Deploy a service via .env + Helm + Ingress
# Sherlock & Angel, July 2025

set -euo pipefail

# 📥 Load env file from CLI
ENV_FILE="${1:-}"

if [[ -z "$ENV_FILE" || ! -f "$ENV_FILE" ]]; then
  echo "❌ Missing or invalid ENV file: $ENV_FILE"
  echo "   Usage: $0 path/to/service.env"
  exit 1
fi

source "$ENV_FILE"

# 🔍 Validate required variables
REQUIRED_VARS=(SERVICE SERVICE_NAME NAMESPACE INGRESS_HOST HELM_REPO_NAME HELM_REPO_URL)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "❌ Missing required env variable: $var"
    exit 1
  fi
done

echo "🚀 Deploying $SERVICE_NAME [$SERVICE] in namespace: $NAMESPACE"

# 📁 Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$SCRIPT_DIR/utils"
CONFIG_DIR="$SCRIPT_DIR/configs"
VALUES_FILE="$CONFIG_DIR/$SERVICE/${SERVICE}-values.yaml"

export KUBECONFIG="${KUBECONFIG:-$HOME/.helix/kubeconfig.yaml}"

# 📎 Source utilities
if [[ -f "$UTILS_DIR/config.sh" ]]; then
  source "$UTILS_DIR/config.sh"
else
  echo "⚠️ config.sh not found. Skipping additional config sourcing."
fi

# ✅ Check kube context
CONTEXT_NAME=$(kubectl config current-context 2>/dev/null || true)
if [[ -z "$CONTEXT_NAME" ]]; then
  echo "❌ No valid Kubernetes context found (check KUBECONFIG: $KUBECONFIG)"
  exit 1
fi

# 📦 Helm values
if [[ ! -f "$VALUES_FILE" ]]; then
  echo "❌ Missing Helm values file: $VALUES_FILE"
  exit 1
fi

# 🧩 Add Helm repo if not already present
if ! helm repo list | grep -q "$HELM_REPO_NAME"; then
  echo "📦 Adding Helm repo '$HELM_REPO_NAME'..."
  helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"
fi
helm repo update > /dev/null

# 🔐 Optional secret script
if [[ -n "${SECRET_SCRIPT:-}" && -f "$SCRIPT_DIR/$SECRET_SCRIPT" ]]; then
  echo "🔐 Running secret script for $SERVICE..."
  bash "$SCRIPT_DIR/$SECRET_SCRIPT"
fi

# 🛠️ Deploy via Helm
echo "📡 Deploying Helm chart for $SERVICE..."
helm upgrade --install "$SERVICE" "$HELM_REPO_NAME/$SERVICE" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$VALUES_FILE" \
  ${HELM_EXTRA_ARGS:-}

# 🌍 Print access info
echo ""
echo "✅ $SERVICE_NAME deployed successfully!"
echo "🌐 Access at: https://${INGRESS_HOST}"
