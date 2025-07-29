#!/usr/bin/env bash
set -euo pipefail
echo "✅ [vault.sh] Loaded!"
# Load identity environment variables
ENV_FILE="${ENV_FILE:-bootstrap/support/identity.env}"
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
else
  echo "❌ Cannot find identity.env at $ENV_FILE"
  exit 1
fi

# Default values
VAULT_NAMESPACE="${NAMESPACE:-vault}"
VAULT_RELEASE="vault-${CLUSTER}"
VAULT_ADDR="http://${VAULT_RELEASE}.${VAULT_NAMESPACE}.svc.cluster.local:8200"
VAULT_TOKEN_PATH="${VAULT_ROOT_TOKEN_FILE:-bootstrap/addon-configs/vault/.vault_root_token}"

deploy_vault() {
  echo "🔐 Deploying Vault to namespace: ${VAULT_NAMESPACE}"

  helm uninstall "$VAULT_RELEASE" -n "$VAULT_NAMESPACE" --ignore-not-found || true
  kubectl create namespace "$VAULT_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

  helm upgrade --install "$VAULT_RELEASE" hashicorp/vault \
    --namespace "$VAULT_NAMESPACE" \
    --set "server.dev.enabled=true" \
    --wait \
    --timeout 300s

  echo "🔍 Waiting for Vault pod to be ready..."
  kubectl rollout status statefulset "$VAULT_RELEASE" -n "$VAULT_NAMESPACE" --timeout=300s

  echo "📦 Vault deployed successfully!"
  save_root_token
}

save_root_token() {
  echo "📥 Extracting Vault root token..."

  VAULT_POD=$(kubectl get pods -n "$VAULT_NAMESPACE" -l "app.kubernetes.io/instance=$VAULT_RELEASE" -o jsonpath="{.items[0].metadata.name}")

  if [[ -z "$VAULT_POD" ]]; then
    echo "❌ Could not find Vault pod."
    exit 1
  fi

  VAULT_TOKEN=$(kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- printenv VAULT_DEV_ROOT_TOKEN_ID)
  if [[ -z "$VAULT_TOKEN" ]]; then
    echo "❌ Vault root token not found in pod environment."
    exit 1
  fi

  echo "$VAULT_TOKEN" > "$VAULT_TOKEN_PATH"
  echo "🔑 Root token saved to: $VAULT_TOKEN_PATH"
}
