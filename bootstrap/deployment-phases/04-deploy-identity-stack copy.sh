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


# Now, use $CLUSTER consistently for derived variables
CLUSTER=${CLUSTER_INPUT:-helix}
DOMAIN=$CLUSTER 
NAMESPACE="identity"
POSTGRES_RELEASE="postgresql-${CLUSTER}"
KEYCLOAK_RELEASE="keycloak-${CLUSTER}"
PG_DATABASE="${POSTGRES_RELEASE}-db"
DB_FQDN="${POSTGRES_RELEASE}.${NAMESPACE}.svc.cluster.local"
PG_USER="keycloak"
PG_PASS="pg_pass"
KC_ADMIN="admin"
KC_PASS="admin"
DEBUG=false
echo "📌 Using cluster: $CLUSTER" # Changed from CLUSTER_NAME to CLUSTER for consistency

# Function to handle errors
error() {
    echo "Error: $1"
    exit 1
}

# Parse CLI args
for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=true ;;
  esac
done

$DEBUG && set -x

# Debug log function
debug_log() {
    $DEBUG && echo -e "🧪 [DEBUG] $*"
}

# Color codes
NC='\033[0m' # No Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'   
BRIGHT_GREEN='\033[1;32m'   

echo -e "${CYAN}🚀 Deploying Identity Stack (Postgres + Keycloak)...${NC}"

# --- Start of KUBECONFIG and Initial Setup ---
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KUBECONFIG_PATH="${KUBECONFIG:-/home/angel/.helix/kubeconfig.yaml}"
export KUBECONFIG="$KUBECONFIG_PATH"

echo -e "${YELLOW}Using Kubeconfig: ${NC}${BRIGHT_GREEN}$KUBECONFIG${NC}"

# Determine cluster name
CLUSTER=${CLUSTER:-$(kubectl config current-context | sed 's/^k3d-//')}
export CLUSTER

if [[ -z "$CLUSTER" ]]; then
  error "Unable to determine cluster name (CLUSTER is empty)"
fi

# Verify kubeconfig existence
if [[ ! -f "$KUBECONFIG_PATH" ]]; then
    echo "⚠️ Kubeconfig not found. Attempting to generate it..."
    source "$HOME/helix_v3/utils/bootstrap/generate_kubeconfig.sh"
    generate_kubeconfig_from_k3d "helix" "$KUBECONFIG_PATH" || error "Kubeconfig generation failed."
fi

source "$HOME/helix_v3/utils/bootstrap/set-kubeconfig.sh" || error "Failed to source set-kubeconfig.sh"

# Verify kubectl connectivity
CONTEXT_NAME=$(kubectl config current-context 2>/dev/null || echo "")
if [[ -z "$CONTEXT_NAME" ]]; then
  error "No valid context found in kubeconfig ($KUBECONFIG)"
fi

echo "🔧 Using kubectl context: $CONTEXT_NAME"
kubectl config use-context "$CONTEXT_NAME" >/dev/null 2>&1 || error "Unable to switch context to $CONTEXT_NAME."
kubectl get ns >/dev/null 2>&1 || error "Unable to connect to Kubernetes API."

echo "✅ Connected to Kubernetes cluster using context: $CONTEXT_NAME"
# --- END of KUBECONFIG and Initial Setup ---

export HELIX_BOOTSTRAP_DIR="$SCRIPT_DIR"
export HELIX_KEYCLOAK_CONFIGS_DIR="./bootstrap/addon-configs/keycloak"

echo -e "${CYAN}Helix Bootstrap Directory: ${NC}${BRIGHT_GREEN}$HELIX_BOOTSTRAP_DIR${NC}"
echo -e "${CYAN}Helix Keycloak Configs Directory: ${NC}${BRIGHT_GREEN}$HELIX_KEYCLOAK_CONFIGS_DIR${NC}"

# Check Traefik Ingress Controller status
echo -e "${CYAN}🔍 Checking Traefik Ingress Controller status...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n kube-system --timeout=180s || {
    echo -e "${RED}Error: Traefik Ingress Controller pods are not ready. Cannot proceed.${NC}"
    exit 1
}
echo -e "${GREEN}✅ Traefik Ingress Controller pods are ready.${NC}"

export TRAEFIK_CLUSTER_IP=$(kubectl get svc -n kube-system -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].spec.clusterIP}')
if [ -z "$TRAEFIK_CLUSTER_IP" ]; then
    error "Could not determine Traefik ClusterIP."
fi

echo -e "${CYAN}Traefik Service ClusterIP: ${BRIGHT_GREEN}$TRAEFIK_CLUSTER_IP${NC}"
VAULT_ENV_FILE="./bootstrap/addon-configs/vault/vault.env"
if [ -f "$VAULT_ENV_FILE" ]; then
    echo "Sourcing Vault environment from $VAULT_ENV_FILE..."
    source "$VAULT_ENV_FILE"
else
    error "Vault environment file not found at $VAULT_ENV_FILE"
fi

# Load Vault Root Token from the dedicated file
VAULT_ROOT_TOKEN_FILE="./bootstrap/addon-configs/vault/.vault_root_token"
if [ -f "$VAULT_ROOT_TOKEN_FILE" ]; then
    echo "Loading Vault Root Token from $VAULT_ROOT_TOKEN_FILE..."
    export VAULT_ROOT_TOKEN=$(cat "$VAULT_ROOT_TOKEN_FILE")
else
    error "Vault Root Token file not found at $VAULT_ROOT_TOKEN_FILE"
fi
echo "Loading Vault utilities..."
source "./utils/bootstrap/vault-utils.sh" || error "Failed to load Vault utilities."
echo "(Re-checking/Initializing with vault-utils.sh) Vault Root Token..."
load_vault_token || error "Failed to verify/initialize Vault. Ensure Vault is unsealed and token is available."

echo "✨ Loaded Vault Root Token"
echo "Vault config:"
echo "   VAULT_NAMESPACE=${VAULT_NAMESPACE}"
echo "   VAULT_RELEASE=${VAULT_RELEASE}"
echo "   VAULT_ADDR=${VAULT_ADDR}"
echo "   VAULT_TOKEN=${VAULT_TOKEN:-}" # Use VAULT_TOKEN as exported from vault.env
echo "   VAULT_ROOT_TOKEN=${VAULT_ROOT_TOKEN:-}" # Use VAULT_ROOT_TOKEN loaded from file

# Check if 'secret/' KV engine is enabled in Vault
echo "🔐 Checking 'secret/' KV engine in Vault..."

enable_kv_if_missing || error "Failed to enable Vault KV engine."
echo "'secret/' KV already enabled."

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🧹 Cleaning leftover PostgreSQL
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "🧹 Cleaning leftover PostgreSQL..."
helm uninstall "$POSTGRES_RELEASE" -n "$NAMESPACE" --wait --timeout 120s 2>/dev/null || true
kubectl delete pvc -n "$NAMESPACE" -l app.kubernetes.io/instance="$POSTGRES_RELEASE" --ignore-not-found --wait=false 2>/dev/null || true
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📦 Deploying PostgreSQL
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "📦 Installing PostgreSQL Repo ..."

helm repo add bitnami https://charts.bitnami.com/bitnami --force-update 2>/dev/null || true

helm repo update 2>/dev/null || true

echo "📦 HELM upgrade --install PostgreSQL..."

if ! helm upgrade --install "$POSTGRES_RELEASE" bitnami/postgresql \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set auth.username="${PG_USER}" \
  --set auth.password="${PG_PASS}" \
  --set auth.database="${PG_DATABASE}" \
  --set primary.persistence.enabled=true \
  --set primary.persistence.size=8Gi \
  --set primary.persistence.storageClass="local-path" \
  --set global.storageClass="" \
  --set primary.resources.requests.cpu="200m" \
  --set primary.resources.requests.memory="256Mi" \
  --set primary.resources.limits.cpu="500m" \
  --set primary.resources.limits.memory="512Mi" \
  --timeout 600s --wait; then
    # stop_spinner 1
    error "PostgreSQL Helm upgrade failed."
fi

echo "Postgres installed successfully!"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📈 Wait for Postgres pod readiness
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "Waiting for 1 Postgres pod to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n "$NAMESPACE" --timeout=300s || {
    # stop_spinner 1
    error "Postgres pod did not become ready in time."
}
echo "Postgres pod is running."

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🔐 Store Postgres credentials in Vault
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "🔍 Store Postgres creds in Vault..."
store_secret "secret/postgresql" \
  username="${PG_USER}" password="${PG_PASS}" \
  database="${PG_DATABASE}" host="${DB_FQDN}" || error "Failed to store Postgres secrets in Vault."
echo "Secrets stored at secret/postgresql 🔒"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📦 Deploying Keycloak
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "📦 Installing Keycloak Repo ..."
helm repo add codecentric https://codecentric.github.io/helm-charts --force-update
helm repo update
echo "📦 HELM upgrade --install Keycloak... "

#############################################
# 🔐 Keycloak Deployment — Dry‑Run + Install
#############################################
deploy_keycloak() {
  echo -e "\n✨ Deploying Keycloak into cluster '${CLUSTER}' (namespace=${NAMESPACE})..."

  local vals="$SCRIPT_DIR/keycloak-values.yaml"

  # 1️⃣ Generate clean values file
  cat >"$vals" <<EOF
auth:
  adminUser: "admin"
  adminPassword: "admin"

externalDatabase:
  host: "postgresql-helix.identity.svc.cluster.local"
  user: "keycloak"
  password: "pg_pass"
  database: "postgresql-helix-db"
  port: 5432

postgresql:
  enabled: false

ingress:
  enabled: true
  ingressClassName: "traefik"
  hostname: "keycloak.helix"
  tls: true
  annotations:
    cert-manager.io/cluster-issuer: "mkcert-ca-issuer"

proxy: edge

extraEnvVars:
  - name: KC_IMPORT_DIR
    value: /opt/keycloak/data/import

extraVolumes:
  - name: helix-theme-volume
    emptyDir: {}

extraVolumeMounts:
  - name: helix-theme-volume
    mountPath: /opt/keycloak/themes

resources:
  requests:
    memory: "1Gi"
    cpu: "200m"
  limits:
    memory: "2Gi"
    cpu: "500m"

readinessProbe:
  httpGet:
    path: /health/ready
    port: 8080
  initialDelaySeconds: 33
  periodSeconds: 10
  timeoutSeconds: 3
  successThreshold: 1
  failureThreshold: 10

livenessProbe:
  httpGet:
    path: /health/live
    port: 8080
  initialDelaySeconds: 60
  periodSeconds: 10
  timeoutSeconds: 3
  successThreshold: 1
  failureThreshold: 5


EOF

  echo "🔍 Values file created at $vals"
  yq . "$vals"

  # 2️⃣ Ensure namespace exists
  if ! kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null; then
    echo "❌ Failed to create/check namespace '$NAMESPACE'"
    return 1
  fi

  # 3️⃣ If previously installed, uninstall cleanly
  if helm status "$KEYCLOAK_RELEASE" -n "$NAMESPACE" &>/dev/null; then
    echo "🔁 Uninstalling existing release '$KEYCLOAK_RELEASE' to avoid ImmutableState error..."
    helm uninstall "$KEYCLOAK_RELEASE" -n "$NAMESPACE" || {
      echo "⚠️ Warning: uninstall failed; continuing anyway"
    }
  fi

  # 4️⃣ Dry‑run validation
  echo "🧪 [Dry‑Run] Validating Helm chart and values..."
  if ! helm upgrade --install "$KEYCLOAK_RELEASE" bitnami/keycloak \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --values "$vals" \
    --debug \
    --dry-run; then
    echo "❌ Dry‑run validation ERROR — fix your values or chart and retry."
    return 1
  fi
  echo "✅ Dry‑run passed."

  # 5️⃣ Helm install with wait
  echo "🚀 Installing Keycloak Helm chart..."
  if ! helm upgrade --install "$KEYCLOAK_RELEASE" bitnami/keycloak \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --values "$vals" \
    --timeout 300s \
    --wait; then
    echo "❌ Helm install failed. To debug: run manually:"
    echo "   helm upgrade --install ${KEYCLOAK_RELEASE} bitnami/keycloak \\\n     --namespace ${NAMESPACE} --values ${vals} --debug --wait"
    return 1
  fi
  echo "✅ Helm install succeeded."

  # 6️⃣ Wait for pod readiness
  echo "⌛ Waiting for Keycloak pod readiness..."
  if ! kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n "$NAMESPACE" --timeout=10m; then
    echo "❌ Pod readiness timeout! Check logs with:"
    echo "   kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=keycloak"
    return 1
  fi
  echo "🎉 Keycloak is ready!"

  # 7️⃣ Ingress (optional)
  cat <<ING >/tmp/keycloak-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak
  namespace: $NAMESPACE
spec:
  rules:
  - host: keycloak.$DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keycloak
            port:
              number: 8080
ING

  if ! kubectl apply -f /tmp/keycloak-ingress.yaml; then
    echo "⚠️ Failed to apply Keycloak ingress; manual fix needed."
  else
    echo "✅ Ingress created: keycloak.$DOMAIN"
  fi

  # 8️⃣ Vault secrets storage
  store_secret "secret/keycloak" \
    admin_username="${KC_ADMIN}" \
    admin_password="${KC_PASS}" \
    url="https://keycloak.${DOMAIN}" || {
      echo "⚠️ Vault storage failed. Please store manually later."
    }
  echo "🔐 Admin cred and URL stored in Vault."

  # Cleanup
  rm -f "$vals" /tmp/keycloak-ingress.yaml

  echo -e "\n✅ Keycloak deployment done: https://keycloak.${DOMAIN} (Admin: ${KC_ADMIN})"
}

# Invoke following Postgres!
deploy_keycloak || {
  echo -e "\n❌ Keycloak deployment step FAILED. Aborting."
  exit 1
}
# Invoke deploy_keycloak function (where appropriate after Postgres)
deploy_keycloak

echo "Keycloak installed successfully!"
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📈 Wait for Keycloak pod readiness
echo "Waiting for 1 Keycloak pod to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n "$NAMESPACE" --timeout=300s || {
    error "Keycloak pod did not become ready in time."
}
echo "Keycloak pod is running."
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🔐 Store Keycloak credentials in Vault
echo "🔍 Store Keycloak creds in Vault..."
store_secret "secret/keycloak" \
  username="${KEYCLOAK_USER}" password="${KEYCLOAK_PASS}" \
  database="${KEYCLOAK_DATABASE}" host="${DB_FQDN}" || error "Failed to store Keycloak secrets in Vault."
echo "Secrets stored at secret/keycloak 🔒"
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🧩 Configure Keycloak with Vault secrets  
echo "🧩 Configuring Keycloak with Vault secrets..."
if ! kubectl exec -n "$NAMESPACE" "$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')" -- \
  /opt/keycloak/bin/kc.sh config credentials \
  --db=postgres \
  --db-url="jdbc:postgresql://${DB_FQDN}:5432/${PG_DATABASE}" \
  --db-username="${PG_USER}" \
  --db-password="$(vault kv get -field=password secret/postgresql)" \
  --db-database="${PG_DATABASE}" \
  --db-host="${DB_FQDN}" \
  --db-port=5432 \
  --admin-username="${KC_ADMIN}" \
  --admin-password="$(vault kv get -field=password secret/keycloak)" \
  --db-vault-addr="${VAULT_ADDR}" \
  --db-vault-token="${VAULT_ROOT_TOKEN}" \
  --db-vault-namespace="${VAULT_NAMESPACE}" \
  --db-vault-path="secret/postgresql" \
  --db-vault-role="keycloak" \
  --db-vault-username-field="username" \
  --db-vault-password-field="password" \
  --db-vault-database-field="database" \
  --db-vault-host-field="host" \
  --db-vault-port-field="port" \
  --db-vault-ssl-mode="disable"; then
    error "Failed to configure Keycloak with Vault secrets."
fi  
echo "Keycloak configured with Vault secrets successfully!"
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🌐 Expose Keycloak via Ingress
echo "🌐 Exposing Keycloak via Ingress..."
if ! kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak
  namespace: $NAMESPACE
spec:
  rules:
  - host: $KEYCLOAK_HOST
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $KEYCLOAK_SERVICE
            port:
              number: 8080
EOF
then
  error "Failed to expose Keycloak via Ingress."
fi    
echo "Keycloak exposed via Ingress successfully!"
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📝 Store Keycloak Ingress URL in Vault
store_secret "secret/keycloak" \
  url="http://${KEYCLOAK_HOST}" || error "Failed to store Keycloak Ingress URL in Vault."
echo "Keycloak Ingress URL stored in Vault 🔒 "
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📝 Store Keycloak Admin credentials in Vault
store_secret "secret/keycloak" \
  admin_username="${KC_ADMIN}" admin_password="$(vault kv get -field=password secret/keycloak)" || error "Failed to store Keycloak Admin credentials in Vault."     
echo "Keycloak Admin credentials stored in Vault 🔒 "
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📝 Store Keycloak configuration in Vault
store_secret "secret/keycloak" \
  realm="${KEYCLOAK_REALM}" client_id="${KEYCLOAK_CLIENT_ID}" client_secret="$(vault kv get -field=client_secret secret/keycloak)" || error "Failed to store Keycloak configuration in Vault."
echo "Keycloak configuration stored in Vault 🔒 "
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📝 Store Keycloak Client Secret in Vault
store_secret "secret/keycloak" \
  client_secret="$(vault kv get -field=client_secret secret/keycloak)" || error "Failed to store Keycloak Client Secret in Vault."
echo "Keycloak Client Secret stored in Vault 🔒 " 
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📝 Store Keycloak Realm in Vault
store_secret "secret/keycloak" \
  realm="${KEYCLOAK_REALM}" || error "Failed to store Keycloak Realm in Vault."
echo "Keycloak Realm stored in Vault 🔒 " 
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📝 Store Keycloak Client ID in Vault
store_secret "secret/keycloak" \
  client_id="${KEYCLOAK_CLIENT_ID}" || error "Failed to store Keycloak Client ID in Vault."
echo "Keycloak Client ID stored in Vault 🔒 "
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📝 Store Keycloak Host in Vault
store_secret "secret/keycloak" \
  host="${KEYCLOAK_HOST}" || error "Failed to store Keycloak Host in Vault."
echo "Keycloak Host stored in Vault 🔒 "  
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📝 Store Keycloak Service in Vault
store_secret "secret/keycloak" \
  service="${KEYCLOAK_SERVICE}" || error "Failed to store Keycloak Service in Vault."
echo "Keycloak Service stored in Vault 🔒 "
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📝 Store Keycloak Namespace in Vault
store_secret "secret/keycloak" \
  namespace="${NAMESPACE}" || error "Failed to store Keycloak Namespace in Vault."
echo "Keycloak Namespace stored in Vault 🔒   "
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📝 Store Keycloak Release in Vault
store_secret "secret/keycloak" \
  release="${KEYCLOAK_RELEASE}" || error "Failed to store Keycloak Release in Vault."
echo "Keycloak Release stored in Vault 🔒 "
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━