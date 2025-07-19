#!/bin/bash
# 🧠 Helix Whip — bootstrap/deployment-phases/00_run_all_steps.sh

# ─── Shell Armor ───────────────────────────────────────────────
set -euo pipefail
shopt -s failglob

VERSION="v0.0.3-beta"
echo "🔐 Helix Deployment Bootstrap — ${VERSION}"

# ─── Resolve Paths ─────────────────────────────────────────────
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
DEPLOY_PHASES_DIR="${SCRIPT_DIR}"

# Go two levels up to get the project root (helix_v3/)
HELIX_ROOT_DIR="$(realpath "$SCRIPT_DIR/../..")"
export HELIX_ROOT_DIR

# ─── Load Env Loader ───────────────────────────────────────────
ENV_LOADER_PATH="${HELIX_ROOT_DIR}/bootstrap_env_loader.sh"

if [[ ! -f "$ENV_LOADER_PATH" ]]; then
  echo "❌ ERROR: bootstrap_env_loader.sh not found at: $ENV_LOADER_PATH"
  exit 1
fi
source "$ENV_LOADER_PATH"

# ─── Validation ────────────────────────────────────────────────
UTILS_DIR="${SCRIPT_DIR}/utils"
if [[ ! -d "$UTILS_DIR" ]]; then
  echo "❌ ERROR: utils directory missing at: $UTILS_DIR"
  exit 1
fi
echo "🐧 UTILS_DIR: $UTILS_DIR"
# ─── Load Utilities ────────────────────────────────────────────
source "${UTILS_DIR}/core/spinner_utils.sh"
source "${UTILS_DIR}/core/print_helix_banner.sh"
source "${UTILS_DIR}/core/deploy-footer.sh"
source "${UTILS_DIR}/core/cluster_info.sh"


echo "🧭 🚀 🌍 🔐 RUNNING bootstrap\deployment-phases\03-vault-bootstrap-unseal.sh"

export SPINNER_FRAMES="🧭 🚀 🌍 🔐"
export SPINNER_INTERVAL=0.2
trap stop_spinner EXIT
DEBUG=false
for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=true ;;
  esac
done
$DEBUG && set -x
if $DEBUG; then
  echo "🔎 DEBUG MODE ENABLED"
  set -x
fi

echo "🔐 Vault bootstrap starting..."
echo -e "🔐 Vault Bootstrap & Unseal 🧱"
echo "🔍 Available k3d clusters:"
k3d cluster list | awk 'NR>1 {print "🔥 " $1}'
echo "[$(date +'%Y-%m-%d %H:%M:%S %Z')] [INFO] Ensuring KUBECONFIG is patched for this session..."
CLUSTER=${CLUSTER_INPUT:-helix}
NAMESPACE="${NAMESPACE:-vault}"
RELEASE="${RELEASE:-vault-${CLUSTER}}"

VAULT_CONFIG_DIR="bootstrap/addon-configs/vault"

VAULT_SECRETS_FILE="./bootstrap/support/vault-secrets-${CLUSTER}.txt"
export KUBECONFIG="${KUBECONFIG:-$HOME/.helix/kubeconfig.yaml}"

VAULT_SERVICE_DNS="${RELEASE}.${NAMESPACE}.svc.cluster.local"
export VAULT_ADDR="https://${VAULT_SERVICE_DNS}:8200"

KUBECONFIG="${KUBECONFIG:-$HOME/.helix/kubeconfig.yaml}"
CURRENT_SERVER=$(kubectl config view --kubeconfig="$KUBECONFIG" -o jsonpath="{.clusters[?(@.name==\"k3d-${CLUSTER}\")].cluster.server}")
if [[ "$CURRENT_SERVER" != "https://127.0.0.1:6550" ]]; then
  echo "🔧 Patching KUBECONFIG to 127.0.0.1:6550"
  kubectl config set-cluster "k3d-${CLUSTER}" \
    --server="https://127.0.0.1:6550" \
    --kubeconfig="$KUBECONFIG"
fi
#######################################################################
echo ""
read -t 10 -p "🌠 Enter cluster name [default: helix]: " CLUSTER_INPUT || CLUSTER_INPUT=""
CLUSTER="${CLUSTER_INPUT:-helix}"
if [[ -z "$CLUSTER_INPUT" ]]; then
  echo "⏳ No input received in 10s — using default: helix"
fi
echo "📌 Using cluster: $CLUSTER"
# Valid
export VAULT_ADDR="https://${RELEASE}.${NAMESPACE}.svc.cluster.local:8200"
export KUBECONFIG="${KUBECONFIG:-$HOME/.helix/kubeconfig.yaml}"
# Validate it's correct
CURRENT_SERVER=$(kubectl config view --kubeconfig="${KUBECONFIG}" -o jsonpath="{.clusters[?(@.name==\"k3d-${CLUSTER}\")].cluster.server}")
if [[ "$CURRENT_SERVER" != "https://127.0.0.1:6550" ]]; then
  echo "🔧 Patching KUBECONFIG to point to k3d API on localhost:6550..."
  kubectl config set-cluster "k3d-${CLUSTER}" \
    --server="https://127.0.0.1:6550" \
    --kubeconfig="${KUBECONFIG}"
fi
echo "[$(date +'%Y-%m-%d %H:%M:%S %Z')] [SUCCESS] Kubeconfig confirmed and updated."
echo -e "\n🐳 Ensuring namespace '$NAMESPACE'"
kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
# ─────────────────────────────────────────────
# Cleanup Function
# ─────────────────────────────────────────────
cleanup_vault() {
  echo "🧼 Cleaning Helm release 'postgresql-helix' in namespace 'identity'..."
  helm uninstall "$RELEASE" --namespace "$NAMESPACE"  --ignore-not-found  || true
  kubectl delete ns "$NAMESPACE" --ignore-not-found || true
  echo "🧹 Deleting PVCs related to Vault..."
  kubectl get pvc -n "$NAMESPACE" -o name | grep vault || true | while read -r pvc; do
    echo "   - $pvc"
    kubectl delete "$pvc" -n "$NAMESPACE" || true
  done
  if [ -f "$VAULT_SECRETS_FILE" ]; then
    echo "🗑️ NOT Removing existing secrets file: $VAULT_SECRETS_FILE"
    # rm -f "$VAULT_SECRETS_FILE"
  fi
  echo "✅ Vault residuls cleaned up. Now, simply re-run script again to create fresh Vault."
  exit 0
}
# ─────────────────────────────────────────────
# Existing Deployment Check
# ─────────────────────────────────────────────
echo "🔍 Checking for existing Vault release..."
if helm status "$RELEASE" -n "$NAMESPACE" &>/dev/null; then
  echo "⚠️ Vault release '$RELEASE' exists."
  read -p "Do you want to clean it up and start fresh? (y/N): " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    cleanup_vault
  fi
fi
# ─────────────────────────────────────────────
# Helm Install/Upgrade
# ─────────────────────────────────────────────
  OPERATION_MSG="📦 Installing or upgrading Vault via Helm..."
#  start_spinner "🔧 $OPERATION_MSG..."

      REPO_NAME="hashicorp"
      REPO_URL="https://helm.releases.hashicorp.com"
      if ! helm repo list | grep -q "$REPO_NAME"; then
        echo "📦 Adding Helm repository: $REPO_NAME"
        helm repo add "$REPO_NAME" "$REPO_URL" --force-update
      else
        echo "📦 Helm repository '$REPO_NAME' already exists. Skipping 'helm repo add'."
      fi
helm repo update
HELM_DEFAULT_VAULT_VALUES_FILE="$VAULT_CONFIG_DIR/vault_default_values.yaml"
VAULT_INGRESS_FILE="$VAULT_CONFIG_DIR/vault-ingressroute.yaml"

if ! yq e . "$HELM_DEFAULT_VAULT_VALUES_FILE" >/dev/null 2>&1; then
  echo "❌ YAML file invalid: $HELM_DEFAULT_VAULT_VALUES_FILE"
  exit 1
fi
echo "✅ YAML file valid: $HELM_DEFAULT_VAULT_VALUES_FILE"
echo "🔄 Deploying Vault... Please wait"
printf "✅ %s complete\n" "$OPERATION_MSG"

helm upgrade --install "$RELEASE" hashicorp/vault \
  --namespace "$NAMESPACE" --create-namespace \
  -f "$HELM_DEFAULT_VAULT_VALUES_FILE" \
  --timeout 3m \
    --wait
    
echo ""
echo "🌐 Applying IngressRoute for Vault UI..."

kubectl apply -f $VAULT_INGRESS_FILE
  OPERATION_MSG="🔁 Restarting Vault Pod to ensure Ingress sync..."

kubectl rollout restart statefulset $RELEASE -n $NAMESPACE

echo "🔐 Vault deployed. Visit https://vault.helix after cert install"
printf "✅ %s complete\n" "$OPERATION_MSG"
echo "✅ Vault Helm deployment complete."
# ─────────────────────────────────────────────
# Wait for Pod to Run
# ─────────────────────────────────────────────
echo -e "\n⏳ Waiting for Vault pod to be running..."
VAULT_POD=""
PHASE="Unknown"
for i in {1..10}; do
  VAULT_POD=$(kubectl get pods -n "$NAMESPACE" \
    -l app.kubernetes.io/instance="$RELEASE",app.kubernetes.io/name=vault \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

  if [[ -n "$VAULT_POD" ]]; then
    PHASE=$(kubectl get pod "$VAULT_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' || echo "Unknown")
    if [[ "$PHASE" == "Running" ]]; then
      echo "✅ Vault pod '$VAULT_POD' is running."
      break
    fi
  fi
  echo "⏳ [$i/10] Waiting for pod... (current phase: $PHASE)"
  sleep 2
done

[[ "$PHASE" != "Running" ]] && {
  echo "❌ Pod '$VAULT_POD' is not running. Aborting."
  kubectl describe pod "$VAULT_POD" -n "$NAMESPACE"
  exit 1
}
# ─────────────────────────────────────────────
# Wait for Vault Service Readiness
# ─────────────────────────────────────────────
echo -e "\n🔍 Checking Vault readiness..."

for i in {1..10}; do
  STATUS_JSON=$(kubectl exec -n "$NAMESPACE" "$VAULT_POD" -- \
    env VAULT_ADDR="http://127.0.0.1:8200" vault status -format=json 2>/dev/null || echo "")

  if echo "$STATUS_JSON" | jq -e '.sealed != null' >/dev/null 2>&1; then
    IS_INITIALIZED=$(jq -r '.initialized' <<< "$STATUS_JSON")
    IS_SEALED=$(jq -r '.sealed' <<< "$STATUS_JSON")

    echo "🔎 Vault Status: initialized=$IS_INITIALIZED, sealed=$IS_SEALED"

    if [[ "$IS_INITIALIZED" == "true" || "$IS_INITIALIZED" == "false" ]]; then
      echo "✅ Vault is responding — proceeding with next step."
      break
    fi
  fi

  echo "⏳ [$i/10] Waiting for Vault API..."
  sleep 5
done

# Final check: validate status output
if [ -z "$STATUS_JSON" ] || ! echo "$STATUS_JSON" | jq -e '.' >/dev/null 2>&1; then
  echo "❌ Vault status check failed or returned invalid JSON"
  echo "Last received: $STATUS_JSON"
  exit 1
fi

echo "$STATUS_JSON" | jq || { echo "❌ Invalid Vault status JSON"; exit 1; }
if [ -z "$STATUS_JSON" ] || ! echo "$STATUS_JSON" | jq -e '.' &>/dev/null; then
  echo "❌ Vault API did not respond or returned invalid JSON after multiple attempts."
  echo "Last received status: '$STATUS_JSON'" # Print for debugging
  exit 1
fi
echo "$STATUS_JSON" | jq || { echo "❌ Invalid Vault status JSON"; exit 1; }
IS_INITIALIZED=$(jq -r '.initialized' <<< "$STATUS_JSON")
IS_SEALED=$(jq -r '.sealed' <<< "$STATUS_JSON")
echo -e "\n💡 initialized=$IS_INITIALIZED sealed=$IS_SEALED\n"
UNSEAL_KEY=""
ROOT_TOKEN=""
DEPLOYMENT_TOKEN=""
# ────────────────────────────────────────────
# Vault Initialization & Policy Setup
# ─────────────────────────────────────────────
export VAULT_ADDR="http://127.0.0.1:8200"
# Add VAULT_SKIP_VERIFY for initial testing if needed, but aim to remove it
export VAULT_SKIP_VERIFY="true" # Temporarily, for development

if [[ "$IS_INITIALIZED" == "false" ]]; then
  echo "🔐 Initializing Vault..."
  INIT_JSON=$(kubectl exec -n "$NAMESPACE" "${RELEASE}-0" -- \
    env VAULT_ADDR="$VAULT_ADDR" vault operator init -key-shares=1 -key-threshold=1 -format=json)

  UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' <<< "$INIT_JSON")
  ROOT_TOKEN=$(jq -r '.root_token' <<< "$INIT_JSON")

  echo "✅ Vault initialized. Unsealing now..."
  kubectl exec -n "$NAMESPACE" "${RELEASE}-0" -- \
    env VAULT_ADDR="$VAULT_ADDR" vault operator unseal "$UNSEAL_KEY"

  echo "🔐 Writing deployment automation policy..."
  kubectl cp ./$VAULT_CONFIG_DIR/policies/deployment-automation-policy.hcl "$VAULT_POD":/tmp/ -n "$NAMESPACE"
  kubectl exec -n "$NAMESPACE" "$VAULT_POD" -- \
    sh -c "env VAULT_ADDR='$VAULT_ADDR' VAULT_TOKEN='$ROOT_TOKEN' vault policy write deployment-automation-policy /tmp/deployment-automation-policy.hcl"

  echo "🔑 Creating deployment token..."
  DEPLOYMENT_TOKEN=$(kubectl exec -n "$NAMESPACE" "$VAULT_POD" -- \
    env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$ROOT_TOKEN" \
    vault token create -policy=deployment-automation-policy -format=json \
    | jq -r '.auth.client_token')

  echo "🗝️ Storing secrets in $VAULT_SECRETS_FILE"
  {
    echo "Vault Unseal Key: $UNSEAL_KEY"
    echo "Vault Root Token: $ROOT_TOKEN"
    echo "Vault Deployment Token: $DEPLOYMENT_TOKEN"
  } > "$VAULT_SECRETS_FILE"
  chmod 600 "$VAULT_SECRETS_FILE"
  echo "✅ Secrets saved."

elif [[ "$IS_SEALED" == "true" ]]; then
  echo "🔐 Vault is sealed."
  if [[ -f "$VAULT_SECRETS_FILE" ]]; then
    UNSEAL_KEY=$(grep "Vault Unseal Key:" "$VAULT_SECRETS_FILE" | awk '{print $4}')
    DEPLOYMENT_TOKEN=$(grep "Vault Deployment Token:" "$VAULT_SECRETS_FILE" | awk '{print $4}')
    echo "🔓 Using saved unseal key..."
  else
    read -p "Enter unseal key: " UNSEAL_KEY
  fi

  kubectl exec -n "$NAMESPACE" "${RELEASE}-0" -- \
    env VAULT_ADDR="$VAULT_ADDR" vault operator unseal "$UNSEAL_KEY"
  echo "✅ Vault unsealed."
  ROOT_TOKEN=$(grep "Vault Root Token:" "$VAULT_SECRETS_FILE" | awk '{print $4}' || true)

else
  echo "✅ Vault already initialized and unsealed."
  [[ -f "$VAULT_SECRETS_FILE" ]] && {
    UNSEAL_KEY=$(grep "Vault Unseal Key:" "$VAULT_SECRETS_FILE" | awk '{print $4}')
    ROOT_TOKEN=$(grep "Vault Root Token:" "$VAULT_SECRETS_FILE" | awk '{print $4}')
    DEPLOYMENT_TOKEN=$(grep "Vault Deployment Token:" "$VAULT_SECRETS_FILE" | awk '{print $4}')
  }
fi
echo "✅ Vault bootstrap complete."

# ─────────────────────────────────────────────
# Final Output
# ─────────────────────────────────────────────
kubectl exec -n "$NAMESPACE" "${RELEASE}-0" -- env VAULT_ADDR="$VAULT_ADDR" vault status
echo -e "\n🔒 Vault is operational and ready."
export VAULT_ADDR="$VAULT_ADDR"
VAULT_ENV_FILE="./$VAULT_CONFIG_DIR/vault.env"
VAULT_ROOT_TOKEN_FILE="./$VAULT_CONFIG_DIR/.vault_root_token" # Define where the root token will be saved

printf "✅ %s complete\n" "$OPERATION_MSG"
# After successful deploy and token generation:
echo -e "\n🔑 Environment exported:"
echo "VAULT_ADDR=${VAULT_ADDR}"
echo "  DEPLOYMENT_TOKEN=${DEPLOYMENT_TOKEN}"
echo "  VAULT_NAMESPACE=${NAMESPACE}"
echo "  VAULT_RELEASE=${RELEASE}"
echo "      🔒🔑.env VAULT_ENV_FILE=${VAULT_ENV_FILE}"
echo "      🔑🔒.yaml pre-defined VAULT_HELM_VALUES=${HELM_DEFAULT_VAULT_VALUES_FILE}"

# 🔒 Generate vault config .env for reuse in other scripts
cat <<EOF > "$VAULT_ENV_FILE"
export VAULT_ADDR="$VAULT_ADDR"
export VAULT_TOKEN="$DEPLOYMENT_TOKEN"
export VAULT_NAMESPACE=$NAMESPACE
export VAULT_RELEASE=$RELEASE
EOF

echo "✅ Vault environment file updated: $VAULT_ENV_FILE"
chmod 600 "$VAULT_ENV_FILE"
echo "✅ Saved Vault environment to $VAULT_ENV_FILE"

# Store the ROOT_TOKEN in a separate, secure file
echo "$ROOT_TOKEN" > "$VAULT_ROOT_TOKEN_FILE"
chmod 600 "$VAULT_ROOT_TOKEN_FILE"
echo "✅ Saved Vault Root Token to $VAULT_ROOT_TOKEN_FILE"

# Optional: also update .env file (only if it exists already)
cp "$VAULT_ENV_FILE" "$VAULT_ENV_FILE" 2>/dev/null || true