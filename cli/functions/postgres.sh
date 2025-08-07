#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR
# cli/functions/postgres.sh

set -euo pipefail

NC='\033[0m' # No Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'   
MAGENTA='\033[1;35m'    
BRIGHT_GREEN='\033[1;32m'   
echo -e "${CYAN}🚀 Deploying Identity Stack (Postgres + Keycloak)...${NC}"
# --- Simple Braille Spinner ---
braille_spinner() {
  local msg="$1"
  local chars=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  local i=0
  while :; do
    printf "\r${CYAN}%s${NC} %s " "${chars[$i]}" "$msg"
    i=$(( (i + 1) % 10 ))
    sleep 0.1
  done
}
# Detect current script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load additional spinner utility if available (for compatibility)
if [[ -f "$SCRIPT_DIR/utils/banner_spinner.sh" ]]; then
    source "$SCRIPT_DIR/utils/banner_spinner.sh" 2>/dev/null || true
fi
# Always use the standard kubeconfig path, or what's already set
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.helix/kubeconfig.yaml}"
export KUBECONFIG="$KUBECONFIG_PATH"
echo -e "${YELLOW}Using Kubeconfig: ${NC}${BRIGHT_GREEN}$KUBECONFIG${NC}"
# Verify kubeconfig existence (optional but good practice)
if [[ ! -f "$KUBECONFIG_PATH" ]]; then
    echo "⚠️ Kubeconfig not found. Attempting to generate it..."
    source "$HOME/helix/bootstrap/utils/generate_kubeconfig.sh"
    generate_kubeconfig_from_k3d "helix" "$KUBECONFIG_PATH" || { echo "❌ Kubeconfig generation failed."; exit 1; }
fi
source "$HOME/helix/utils/bootstrap/set-kubeconfig.sh" || { echo "❌ Failed to source set-kubeconfig.sh"; exit 1; }
# Verify kubectl connectivity *after* KUBECONFIG is set and potentially patched
CONTEXT_NAME=$(kubectl config current-context 2>/dev/null || echo "")
if [[ -z "$CONTEXT_NAME" ]]; then
  echo "❌ No valid context found in kubeconfig ($KUBECONFIG)"
  exit 1
fi
echo "🔧 Using kubectl context: $CONTEXT_NAME"
if ! kubectl config use-context "$CONTEXT_NAME" >/dev/null 2>&1; then
  echo "❌ Unable to switch context to $CONTEXT_NAME. Check your kubeconfig."
  exit 1
fi
if ! kubectl get ns >/dev/null 2>&1; then
  echo "❌ Unable to connect to Kubernetes API. Check cluster status or certificates."
  exit 1
fi
echo "✅ Connected to Kubernetes cluster using context: $CONTEXT_NAME"
# --- END of KUBECONFIG and Initial Setup ---
export HELIX_BOOTSTRAP_DIR="$(dirname "$SCRIPT_DIR")"
export HELIX_KEYCLOAK_CONFIGS_DIR="$HELIX_BOOTSTRAP_DIR/addon-configs/keycloak"
echo -e "${CYAN}Helix Bootstrap Directory: ${NC}${BRIGHT_GREEN}$HELIX_BOOTSTRAP_DIR${NC}"
echo -e "${CYAN}Helix Keycloak Configs Directory: ${NC}${BRIGHT_GREEN}$HELIX_KEYCLOAK_CONFIGS_DIR${NC}"
# --- Now, this TRAEFIK_CLUSTER_IP check should work ---
echo -e "${CYAN}🔍 Checking Traefik Ingress Controller status...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n kube-system --timeout=180s || {
    echo -e "${RED}Error: Traefik Ingress Controller pods are not ready. Cannot proceed.${NC}"
    exit 1
}
echo -e "${GREEN}✅ Traefik Ingress Controller pods are ready.${NC}"

export TRAEFIK_CLUSTER_IP=$(kubectl get svc -n kube-system -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].spec.clusterIP}')
if [ -z "$TRAEFIK_CLUSTER_IP" ]; then
    echo -e "${RED}Error: Could not determine Traefik ClusterIP. Exiting.${NC}"
    exit 1
fi
echo -e "${CYAN}Traefik Service ClusterIP: ${BRIGHT_GREEN}$TRAEFIK_CLUSTER_IP${NC}"
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
# Correct way to define the base Keycloak config directory
HELIX_KEYCLOAK_CONFIGS_DIR="${SCRIPT_DIR}/../addon-configs/keycloak"

# The rest of your definitions will then be correct relative to this base
THEME_DIR="${HELIX_KEYCLOAK_CONFIGS_DIR}/themes/${CLUSTER}"
REALM_JSON="${HELIX_KEYCLOAK_CONFIGS_DIR}/realms/helix-realm.json"

echo "Resolved SCRIPT_DIR: ${SCRIPT_DIR}"
echo "Resolved HELIX_KEYCLOAK_CONFIGS_DIR: ${HELIX_KEYCLOAK_CONFIGS_DIR}"
echo "Resolved REALM_JSON: ${REALM_JSON}"
echo "🔧 Using Theme Directory: $THEME_DIR"
echo "🔧 Using Realm JSON File: $REALM_JSON"
echo "📦 Namespace: $NAMESPACE"
echo "📌 Using cluster: $CLUSTER"

# ─────────────────────────────────────────────
# Kubeconfig and Namespace Setup
# Validate it's correct 
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
echo -e "${GREEN}✅ Namespace '$NAMESPACE' is ready.${NC}"
# ─────────────────────────────────────────────
# Existing Deployment Check
# ─────────────────────────────────────────────
echo "🔍 Checking for existing Vault deployment in namespace '$NAMESPACE'..."
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🔐 Load Vault Root Token (Safe & Robust)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Absolute-safe path handling (resolves project root from script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_TOKEN_FILE="$SCRIPT_DIR/../addon-configs/vault/.vault_root_token"
echo "🔑 Loading Vault Root Token from: $SCRIPT_DIR"
# Check if the Vault token file exists
if [[ -z "$VAULT_TOKEN_FILE" ]]; then
    echo -e "${RED}❌ Vault Root Token is not set. Please ensure it is exported or available in the environment.${NC}"
    echo -e "🕵️‍♂️ Hint: Ensure Vault is unsealed and the token is available."
    exit 1
fi
# Load the Vault Root Token from the file
# This is a safe and robust way to load the token, ensuring it exists before proceeding
if [[ -f "$VAULT_TOKEN_FILE" ]]; then
    echo "🔑 Loading Vault Root Token from: $VAULT_TOKEN_FILE"
    export VAULT_TOKEN_FILE="$(<"$VAULT_TOKEN_FILE")"
else
    echo -e "${RED}❌ Vault Root Token file not found at:${NC} $VAULT_TOKEN_FILE"
    echo -e "🕵️‍♂️ Hint: Did Vault bootstrap complete? Was the token saved?"
    exit 1
fi
# ─────────────────────────────────────────────
# 🔐 Load Vault Root Token (Safe & Robust ) 
# ─────────────────────────────────────────────
if kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE" >/dev/null 2>&1; then
    echo "🔍 Found existing Vault deployment in namespace '$NAMESPACE'."
else
    echo "❌ No existing Vault deployment found in namespace '$NAMESPACE'."
    exit 1
fi
# ─────────────────────────────────────────────
# Load Vault utilities
# ─────────────────────────────────────────────
echo "🔧 Loading Vault utilities..."
# Use absolute path based on SCRIPT_DIR
VAULT_UTILS_PATH="$SCRIPT_DIR/../../utils/bootstrap/vault-utils.sh"
if [[ ! -f "$VAULT_UTILS_PATH" ]]; then
  echo -e "${RED}❌ Vault utility script not found at: $VAULT_UTILS_PATH${NC}"
  echo -e "💡 Ensure you have the correct path and the file exists."
  exit 1
fi

source "$VAULT_UTILS_PATH" || { echo "❌ Failed to source vault-utils.sh"; exit 1; }
echo "🔧 Vault utilities loaded successfully. "
# ─────────────────────────────────────────────
# 🔍 Check if Vault is initialized and unsealed
# ─────────────────────────────────────────────
echo "(Re-checking/Initializing with vault-utils.sh) Vault Root Token..."
load_vault_token || error "Failed to verify/initialize Vault. Ensure Vault is unsealed and token is available."
echo "✨ Loaded Vault Root Token"
echo "Vault config:"
echo "   VAULT_NAMESPACE=${VAULT_NAMESPACE}"
echo "   VAULT_RELEASE=${VAULT_RELEASE}"
echo "   VAULT_ADDR=${VAULT_ADDR}"
echo "   VAULT_TOKEN=${VAULT_TOKEN:-}"
echo "   VAULT_TOKEN_FILE=${VAULT_TOKEN_FILE:-}" 

VAULT_POD_NAME=$(kubectl get pods -n "$VAULT_NAMESPACE" -l \
  app.kubernetes.io/instance="$VAULT_RELEASE" -o jsonpath='{.items[0].metadata.name}') || \
  { echo "❌ Could not find Vault pod"; exit 1; }
####### Utility Functions ##############
enable_kv_if_missing() {
  echo "🔐 Checking 'secret/' KV engine in Vault..."
  if ! kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD_NAME" -- \
      sh -c "VAULT_ADDR=$VAULT_ADDR VAULT_TOKEN=$VAULT_TOKEN_FILE \
             vault secrets list -format=json" | jq -e '."secret/"' &>/dev/null; then
    echo "🛠️ Enabling 'secret/' KV engine..."
    kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD_NAME" -- \
      sh -c "VAULT_ADDR=$VAULT_ADDR VAULT_TOKEN=$VAULT_TOKEN_FILE \
             vault secrets enable -path=secret kv" || \
      { echo "❌ Enabling KV engine failed"; exit 1; }
  else
    echo "✅ 'secret/' KV already enabled."
  fi
}
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  tput civis
  while ps -p $pid >/dev/null; do
    for i in $(seq 0 ${#spinstr}); do
      printf " [%s] Installing cert-manager...\r" "${spinstr:$i:1}"
      sleep $delay
    done
  done
  tput cnorm
  printf " ✅ cert-manager installed!\n"
}

store_secret() {
  local path="$1"; shift
  local args=("$@")

  echo "💾 Writing secret to Vault at '$path'..."
  echo "    Payload: ${args[*]}"
  kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD_NAME" -- /bin/sh -c "
    VAULT_ADDR='$VAULT_ADDR' VAULT_TOKEN='$VAULT_TOKEN_FILE' \
    vault kv put ${path} ${args[*]}
  " || {
    echo "❌ Failed to store secret at $path"
    exit 1
  }
  echo "✅ Secrets stored at $path 🔒"
}

start_spinner() {
  SPINNER_CHARS='🌑🌒🌓🌔🌕🌖🌗🌘'
  SPINNER_POS=0
  # Redirect printf output to /dev/tty to ensure it's only shown on the terminal
  # and not captured in logs.
  while true; do
    printf "\r🌀 Waiting for Keycloak install... ${SPINNER_CHARS:$SPINNER_POS:1} " >/dev/tty
    SPINNER_POS=$(( (SPINNER_POS + 1) % ${#SPINNER_CHARS} ))
    sleep 0.2
  done
}

start_postgres_spinner() {
  local frames=("🐘    " " 🐘   " "  🐘  " "   🐘 " "    🐘" "   🐘 " "  🐘  " " 🐘   " "🐘    ")
  local i=0
  while true; do
    printf "\r🔄 Setting up Postgres... %s" "${frames[i]}"
    i=$(( (i + 1) % ${#frames[@]} ))
    sleep 0.4
  done
}

cleanup_helm_release() {
    local release=$1 namespace=$2

    echo "🧼 Cleaning Helm release '$release' in namespace '$namespace'..."
    helm uninstall "$release" -n "$namespace" --ignore-not-found  || true

    kubectl delete pvc -n "$namespace" -l app.kubernetes.io/instance="$release" --ignore-not-found || true
}

#################################################
# Step 1 - start of program - Prompt for cluster 
##################################################
echo "🔍 Available k3d clusters:"
k3d cluster list | awk 'NR>1 {print "🔥 " $1}'
# echo ""
# if [ -t 0 ]; then
#   read -t 10 -p "🌠 Enter cluster name [default: helix]: " CLUSTER_INPUT || true
# fi  
# CLUSTER="${CLUSTER_INPUT:-helix}"
echo "📌 Using cluster: $CLUSTER" # Changed from CLUSTER_NAME to CLUSTER for consistency
# Now, use $CLUSTER consistently for derived variables
DOMAIN=$CLUSTER # Assuming DOMAIN is always "cluster" environment
NAMESPACE="identity"
POSTGRES_RELEASE="postgresql-${CLUSTER}"
KEYCLOAK_RELEASE="keycloak-${CLUSTER}"
PG_DATABASE="${POSTGRES_RELEASE}-db"
DB_FQDN="${POSTGRES_RELEASE}.${NAMESPACE}.svc.cluster.local"
PG_USER="keycloak"
PG_PASS="pg_pass"
KC_ADMIN="admin"
KC_PASS="admin"
####### Defined variables #############
echo "✅ Prepared all variables. Beginning deployment..."
# Prepare Vault KV store
enable_kv_if_missing
####### PostgreSQL Deployment #########
echo "🧹 Cleaning leftover PostgreSQL..."
start_postgres_spinner & SPINNER_PID=$!
cleanup_helm_release "$POSTGRES_RELEASE" "$NAMESPACE"
kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kill "$SPINNER_PID" >/dev/null 2>&1 || true
wait "$SPINNER_PID" 2>/dev/null || true
echo ""
echo "📦 Installing PostgreSQL Repo ..."
start_postgres_spinner & SPINNER_PID=$!

REPO_NAME="bitnami"
REPO_URL="https://charts.bitnami.com/bitnami"
if ! helm repo list | grep -q "$REPO_NAME"; then
  echo "📦 Adding Helm repository: $REPO_NAME"
  helm repo add "$REPO_NAME" "$REPO_URL"  --force-update || true
else
  echo "📦 Helm repository '$REPO_NAME' already exists. Skipping 'helm repo add'."
fi

kill "$SPINNER_PID" >/dev/null 2>&1 || true
wait "$SPINNER_PID" 2>/dev/null || true
echo "🎡 Updating Repos ..."

echo ""
   vals="$SCRIPT_DIR/postgresql_values.yaml"
cat <<EOF >${vals}
auth:
  username: ${PG_USER}
  password: ${PG_PASS}
  database: ${PG_DATABASE}
  enablePostgresUser: true
primary:
  pgHbaConfiguration: |
    host all all 0.0.0.0/0 scram-sha-256
    host all all ::/0 scram-sha-256
    local all all scram-sha-256
    host all all 127.0.0.1/32 scram-sha-256
    host all all ::1/128 scram-sha-256
  extendedConfiguration: |-
    password_encryption = 'scram-sha-256'
    max_connections = 75
    shared_buffers = 128MB
    work_mem = 4MB
    effective_cache_size = 512MB
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 250m
service:
  type: ClusterIP
  port: 5432
EOF
echo "📦 HELM upgrade --install PostgreSQL Repo ..."
echo ""
start_postgres_spinner & SPINNER_PID=$!
helm upgrade --install "$POSTGRES_RELEASE" bitnami/postgresql \
  --namespace "$NAMESPACE" \
  -f "$vals" \
  --timeout 300s || \
  { echo "❌ PostgreSQL helm install failed"; exit 1; }
####### PostgreSQL Deployed #########
# rm -f configs/postgres/postgresql_values.yaml
echo ""
kill "$SPINNER_PID" >/dev/null 2>&1 || true
wait "$SPINNER_PID" 2>/dev/null || true
echo -e "\r${BRIGHT_GREEN}✅ Postgres installed successfully!${NC}"
####### PostgreSQL Credentials #########
echo "📡 PostgreSQL deployed:"
echo "  🧑 Username: $PG_USER"
echo "  🔑 Password: $PG_PASS"
echo "  🐘 DB: $PG_DATABASE"
echo "  📡 Host: $DB_FQDN"

kubectl rollout status statefulset "$POSTGRES_RELEASE" -n "$NAMESPACE" --timeout=300s

# Store Postgres creds
enable_kv_if_missing

# --- Before calling store_secret ---

echo -e "${CYAN}🔍 Checking Traefik Ingress Controller status...${NC}"
# Wait for Traefik deployment to be ready (assuming default 'traefik' namespace)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n kube-system --timeout=180s || {
    echo -e "${RED}Error: Traefik Ingress Controller pods are not ready. Cannot proceed.${NC}"
    exit 1
}
echo -e "${GREEN}✅ Traefik Ingress Controller pods are ready.${NC}"

# Check if the Traefik service is exposed on port 443
TRAEFIK_SVC_IP=$(kubectl get svc -n kube-system -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].spec.clusterIP}')
echo -e "${CYAN}Traefik Service ClusterIP: ${BRIGHT_GREEN}$TRAEFIK_SVC_IP${NC}"

# Global variables for Vault pod and namespace (if not already set by previous scripts)
# Set path to token file
VAULT_ENVIRONMENT_FILE="$PWD/bootstrap/addon-configs/vault/vault.env"
VAULT_ROOT_TOKEN_FILE="$PWD/bootstrap/addon-configs/vault/.vault_root_token"

# Load only if token not already set
if [[ -z "${VAULT_ROOT_TOKEN:-}" ]]; then
  if [[ -f "$VAULT_ROOT_TOKEN_FILE" ]]; then
    echo "🔑 Loading Vault Root Token from: $VAULT_ROOT_TOKEN_FILE"
    export VAULT_ROOT_TOKEN="$(<"$VAULT_ROOT_TOKEN_FILE")"
  else
    echo -e "${RED}❌ Vault Root Token file not found at: $VAULT_ROOT_TOKEN_FILE${NC}"
    echo -e "💡 Ensure step 03 (Vault Bootstrap) has completed successfully."
    exit 1
  fi
else
  echo "✅ Vault Root Token already set in environment."
fi
# Fetch Vault POD_NAME (ensure it's dynamic)
export VAULT_POD_NAME=$(kubectl get pods -n "$VAULT_NAMESPACE" -l app.kubernetes.io/name=vault,app.kubernetes.io/instance="$VAULT_RELEASE" --no-headers -o custom-columns=":metadata.name" | head -n 1)
if [ -z "$VAULT_POD_NAME" ]; then
    echo -e "${RED}Error: Vault pod name not found. Exiting.${NC}"
    exit 1
fi
echo -e "${GREEN}Found Vault pod: ${NC}${BRIGHT_GREEN}$VAULT_POD_NAME${NC}"
# Ensure Traefik is ready and get its ClusterIP
echo -e "${CYAN}🔍 Checking Traefik Ingress Controller status...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n kube-system --timeout=180s || {
    echo -e "${RED}Error: Traefik Ingress Controller pods are not ready. Cannot proceed.${NC}"
    exit 1
}
echo -e "${GREEN}✅ Traefik Ingress Controller pods are ready.${NC}"

store_secret "secret/postgresql" \
  username="${PG_USER}" \
  password="${PG_PASS}" \
  database="${PG_DATABASE}" \
  host="${DB_FQDN}"
echo -e "${GREEN}✅ PostgreSQL credentials stored in Vault at 'secret/postgresql'${NC}"
#############################################
