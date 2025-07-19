#!/bin/bash

# utils/bootstrap/generate_kubeconfig.sh
# 🧩 Purpose: Trust mkcert TLS by embedding its root CA into kubeconfig


set -euo pipefail

MKCERT_ROOT_CA_PEM_PATH="$1"
INITIAL_KUBECONFIG_PATH="$2"
FINAL_KUBECONFIG_PATH="$3"

KUBECONFIG_DIR=$(dirname "$FINAL_KUBECONFIG_PATH")
USER_NAME="admin@helix"
CONTEXT_NAME="helix"
CLUSTER_NAME="helix"

mkdir -p "$KUBECONFIG_DIR"

echo "🔧 Bootstrapping kubeconfig setup for cluster '$CLUSTER_NAME'..."
echo "Initial Kubeconfig: $INITIAL_KUBECONFIG_PATH"
echo "Final Output:       $FINAL_KUBECONFIG_PATH"

# 🧬 Base64-encode mkcert root CA
if [[ ! -f "$MKCERT_ROOT_CA_PEM_PATH" ]]; then
    echo "❌ mkcert root CA file not found: $MKCERT_ROOT_CA_PEM_PATH"
    exit 1
fi
CA_DATA=$(base64 -w 0 "$MKCERT_ROOT_CA_PEM_PATH")

# 🧪 Check yq
if ! command -v yq &> /dev/null; then
    echo "❌ 'yq' is required but not found. Install it via 'brew install yq' or 'snap install yq'"
    exit 1
fi

# 🧩 Modify kubeconfig
echo "🧬 Embedding mkcert CA and adjusting names..."
MODIFIED=$(yq '
  .clusters[0].name = strenv(CLUSTER_NAME) |
  .clusters[0].cluster."certificate-authority-data" = strenv(CA_DATA) |
  del(.clusters[0].cluster."certificate-authority") |
  .users[0].name = strenv(USER_NAME) |
  .contexts[0].name = strenv(CONTEXT_NAME) |
  .contexts[0].context.cluster = strenv(CLUSTER_NAME) |
  .contexts[0].context.user = strenv(USER_NAME) |
  .current-context = strenv(CONTEXT_NAME)
' "$INITIAL_KUBECONFIG_PATH")

echo "$MODIFIED" > "$FINAL_KUBECONFIG_PATH"
chmod 600 "$FINAL_KUBECONFIG_PATH"
export KUBECONFIG="$FINAL_KUBECONFIG_PATH"

# ✅ Explicitly set the current context
kubectl config use-context "$CONTEXT_NAME"

echo "✅ Kubeconfig written to: $FINAL_KUBECONFIG_PATH"

# 🔍 Show context info
echo ""
echo "🔍 Current kubectl context info:"
kubectl config get-contexts
kubectl config current-context
kubectl config view --minify


# 🕒 Wait for the API server
echo "🕒 Verifying Kubernetes API connectivity with embedded mkcert CA..."
for i in {1..20}; do
  if kubectl get --raw=/healthz &>/dev/null; then
    echo "✅ API server is reachable and trusted."
    break
  else
    echo "🔄 Attempt $i/20 — waiting for API server..."
    sleep 3
  fi
done

if [[ "$i" -eq 20 ]]; then
  echo "❌ Could not connect to Kubernetes API server with updated kubeconfig."
  exit 1
fi

echo "🧩 Kubeconfig setup complete. Proceeding with cluster bootstrap."
