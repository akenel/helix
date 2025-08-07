#!/bin/bash
# 🔐 Helix OIDC Setup for Vault - Phase 34
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR

# 📁 Load environment from vault.env
VAULT_ENV_FILE="./bootstrap/addon-configs/vault/vault.env"
VAULT_SECRETS_FILE="./bootstrap/support/vault-secrets-helix.txt"

if [[ ! -f "$VAULT_ENV_FILE" ]]; then
  echo "❌ ERROR: vault.env not found at $VAULT_ENV_FILE"
  exit 1
fi

if [[ ! -f "$VAULT_SECRETS_FILE" ]]; then
  echo "❌ ERROR: vault-secrets-helix.txt not found at $VAULT_SECRETS_FILE"
  exit 1
fi

# 📋 Load environment variables
echo "📋 Loading environment..."
source "$VAULT_ENV_FILE"

# 🔑 Extract ROOT token and unseal key from secrets file
echo "🔑 Extracting Vault Root Token and Unseal Key from secrets file..."
VAULT_ROOT_TOKEN=$(grep "Vault Root Token:" "$VAULT_SECRETS_FILE" | cut -d' ' -f4)
VAULT_UNSEAL_KEY=$(grep "Vault Unseal Key:" "$VAULT_SECRETS_FILE" | cut -d' ' -f4)

if [[ -z "$VAULT_ROOT_TOKEN" ]]; then
  echo "❌ ERROR: Could not extract Vault Root Token from $VAULT_SECRETS_FILE"
  exit 1
fi

if [[ -z "$VAULT_UNSEAL_KEY" ]]; then
  echo "❌ ERROR: Could not extract Vault Unseal Key from $VAULT_SECRETS_FILE"
  exit 1
fi

# Override with root token for admin operations
# 👇 Set protocol and address
VAULT_SCHEME=${VAULT_SCHEME:-http}
VAULT_HOST=${VAULT_HOST:-127.0.0.1}
VAULT_PORT=${VAULT_PORT:-8200}
VAULT_ADDR="${VAULT_SCHEME}://${VAULT_HOST}:${VAULT_PORT}"
export VAULT_ADDR
export VAULT_TOKEN="$VAULT_ROOT_TOKEN"
export VAULT_UNSEAL_KEY="$VAULT_UNSEAL_KEY" 
echo "🔐 VAULT_ADDR=$VAULT_ADDR"
echo "🔑 Using Vault ROOT Token: ${VAULT_TOKEN:0:15}********"
echo "🗝️ Using Vault Unseal Key: ${VAULT_UNSEAL_KEY:0:10}********"

# 📦 Find Vault pod (don't wait for readiness - 0/1 is normal for unsealed Vault)
echo "🔎 Locating Vault pod..."
VAULT_POD=$(kubectl get pods -n "$VAULT_NAMESPACE" -l app.kubernetes.io/instance="$VAULT_RELEASE" -o jsonpath='{.items[0].metadata.name}')

if [[ -z "$VAULT_POD" ]]; then
  echo "❌ ERROR: No Vault pod found"
  exit 1
fi

echo "📦 Vault pod found: $VAULT_POD"

# 🔓 Verify Vault is unsealed and accessible (auto-unseal if needed)
echo "🔓 Checking if Vault is unsealed and accessible..."
MAX_RETRIES=30
RETRY_COUNT=0
is_vault_ready() {
 VAULT_POD=$(kubectl get pod -n vault -l "app.kubernetes.io/name=vault" -o jsonpath="{.items[0].metadata.name}")
 kubectl exec -n vault "$VAULT_POD" -- vault status -format=json | jq -r '.sealed' | grep -q 'false'}
kubectl exec -n vault "$VAULT_POD" -- vault status -format=json | jq '.sealed'
if [[ $? -ne 0 ]]; then
  echo "❌ ERROR: Vault pod is not accessible"
  exit 1
fi

}  
# 🌐 Wait for Keycloak to be ready
echo "⏳ Checking Keycloak readiness..."
KEYCLOAK_NAMESPACE=${KEYCLOAK_NAMESPACE:-keycloak}
KEYCLOAK_SERVICE="keycloak"
REALM_NAME="helix3d"
KEYCLOAK_DISCOVERY_URL="https://keycloak.helix/realms/$REALM_NAME"

# Check if Keycloak namespace exists and pods are running (not necessarily ready)
if kubectl get namespace "$KEYCLOAK_NAMESPACE" &>/dev/null; then
  echo "🔍 Checking Keycloak pods in namespace: $KEYCLOAK_NAMESPACE"
  KEYCLOAK_PODS=$(kubectl get pods -n "$KEYCLOAK_NAMESPACE" -l app=keycloak --no-headers 2>/dev/null | wc -l || echo "0")
  if [[ "$KEYCLOAK_PODS" -gt 0 ]]; then
    echo "✅ Found $KEYCLOAK_PODS Keycloak pod(s) running"
  else
    # Try alternative selector
    KEYCLOAK_PODS=$(kubectl get pods -n "$KEYCLOAK_NAMESPACE" -l app.kubernetes.io/name=keycloak --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$KEYCLOAK_PODS" -gt 0 ]]; then
      echo "✅ Found $KEYCLOAK_PODS Keycloak pod(s) running (alternative selector)"
    else
      echo "⚠️  No Keycloak pods found, proceeding anyway..."
    fi
  fi
else
  echo "⚠️  Keycloak namespace '$KEYCLOAK_NAMESPACE' not found, proceeding anyway..."
fi

# Test Keycloak discovery endpoint accessibility (from within cluster)
echo "🌐 Testing Keycloak discovery endpoint accessibility..."
kubectl run test-keycloak-connectivity --rm -i --restart=Never --image=curlimages/curl:latest -- \
  curl -s --max-time 10 "$KEYCLOAK_DISCOVERY_URL/.well-known/openid-configuration" > /dev/null && \
  echo "✅ Keycloak discovery endpoint is accessible" || \
  echo "⚠️  Keycloak discovery endpoint test failed (may be normal if using internal DNS)"

# 🧩 OIDC Config Values
OIDC_CLIENT_ID="vault-integration"
OIDC_CLIENT_SECRET="vault-client-secret"
ROLE_NAME="helix3d-role"

echo "🔗 Keycloak Discovery URL: $KEYCLOAK_DISCOVERY_URL"
echo "🔗 OIDC Client ID: $OIDC_CLIENT_ID"
echo "🔗 OIDC Client Secret: ${OIDC_CLIENT_SECRET}"
echo "🔗 Role Name: $ROLE_NAME"
echo ""

# 🔍 Verify token has sufficient permissions
echo "🔍 Verifying token permissions..."
if ! kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
  vault token lookup &>/dev/null; then
  echo "❌ ERROR: Invalid or expired Vault token"
  exit 1
fi

# Check if token has sys/auth capabilities
TOKEN_CAPABILITIES=$(kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
  vault token capabilities sys/auth/oidc 2>/dev/null || echo "unknown")

echo "🔐 Token capabilities for sys/auth/oidc: $TOKEN_CAPABILITIES"

# 🧪 Enable OIDC (idempotent)
echo "⚙️ Enabling OIDC auth method (if not already enabled)..."
if kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
  vault auth enable oidc 2>/dev/null; then
  echo "✅ OIDC auth method enabled"
else
  # Check if it's already enabled
  if kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
    env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
    vault auth list 2>/dev/null | grep -q "oidc/"; then
    echo "✅ OIDC already enabled"
  else
    echo "❌ ERROR: Failed to enable OIDC auth method"
    echo "💡 Current auth methods:"
    kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
      env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
      vault auth list || echo "Could not list auth methods"
    exit 1
  fi
fi

# 🔗 Configure Vault to trust Keycloak
echo "🔧 Configuring Vault to trust Keycloak (Realm: $REALM_NAME)..."
if kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" vault auth list -format=json | jq '."oidc/"'

    oidc_discovery_url="$KEYCLOAK_DISCOVERY_URL" \
    oidc_client_id="$OIDC_CLIENT_ID" \
    oidc_client_secret="$OIDC_CLIENT_SECRET" \
    default_role="$ROLE_NAME"; then
  echo "✅ OIDC configuration written successfully"
else
  echo "❌ ERROR: Failed to configure OIDC"
  echo "🔍 Checking current OIDC config:"

# 🔍 Detect current OIDC mount path
echo "🔍 Detecting OIDC auth mount path..."
OIDC_PATH=$(kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
  vault auth list -format=json | jq -r 'to_entries[] | select(.value.type=="oidc") | .key')

OIDC_PATH=${OIDC_PATH%/}  # Remove trailing slash if present

if [[ -z "$OIDC_PATH" ]]; then
  echo "❌ ERROR: OIDC auth method not detected in Vault"
  exit 1
fi

echo "📎 OIDC mount path detected: auth/${OIDC_PATH}/"
  VAULT_ADDR=${VAULT_ADDR:-http://vault.helix:8200}
# 🔧 Configure Vault to trust Keycloak (retry-safe)
echo "🔧 Configuring Vault to trust Keycloak (Realm: $REALM_NAME)..."

attempt_oidc_config() {
  kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
    env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
    vault write "auth/${OIDC_PATH}/config" \
      oidc_discovery_url="$KEYCLOAK_DISCOVERY_URL" \
      oidc_client_id="$OIDC_CLIENT_ID" \
      oidc_client_secret="$OIDC_CLIENT_SECRET" \
      default_role="$ROLE_NAME"
}

if attempt_oidc_config; then
  echo "✅ OIDC configuration written successfully"
else
  echo "⚠️ First attempt failed. Retrying in 5 seconds..."
  sleep 5
  if attempt_oidc_config; then
    echo "✅ OIDC configuration written successfully (on retry)"
  else
    echo "❌ ERROR: Failed to configure Vault with OIDC settings"
    echo "🔍 Existing OIDC config (if any):"
    kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
      env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
      vault read "auth/${OIDC_PATH}/config" || echo "None"
    exit 1
  fi
fi

# 🛡️ Create Vault Role for Keycloak Users
echo "👥 Creating OIDC role: $ROLE_NAME"
if kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
  vault write "auth/${OIDC_PATH}/role/$ROLE_NAME" \
    bound_audiences="$OIDC_CLIENT_ID" \
    allowed_redirect_uris="https://vault.helix/ui/vault/auth/oidc/oidc/callback,https://vault.helix/ui/vault/auth/oidc/oidc/callback/" \
    user_claim="preferred_username" \
    policies="default" \
    ttl="1h" \
    max_ttl="24h"; then
  echo "✅ OIDC role '$ROLE_NAME' created successfully"
else
  echo "❌ ERROR: Failed to create OIDC role"
  exit 1
fi

# 🔍 Verify configuration
echo "🔍 Verifying OIDC configuration..."
kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
  vault read "auth/${OIDC_PATH}/config"

echo "📋 OIDC Role '$ROLE_NAME':"
kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
  vault read "auth/${OIDC_PATH}/role/$ROLE_NAME"
echo "📋 Verifying OIDC auth mount:"
if ! kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
  vault list -format=json sys/auth | grep oidc; then
  echo "❌ OIDC auth method not detected. Aborting."
  exit 1
else
  echo "✅ OIDC mount verified."
fi
  echo "🔍 Verifying OIDC configuration..."
  kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
    env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
    vault read "auth/${OIDC_PATH}/config" || echo "No existing OIDC config found"
echo "🔧 Configuring Vault to trust Keycloak via $VAULT_ADDR..."
if ! kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
  vault write "auth/${OIDC_PATH}/config" \
    oidc_discovery_url="$KEYCLOAK_DISCOVERY_URL" \
    oidc_client_id="$OIDC_CLIENT_ID" \
    oidc_client_secret="$OIDC_CLIENT_SECRET" \
    default_role="$ROLE_NAME"; then

  echo "⚠️ First attempt failed. Retrying after 5s..."
  sleep 5
echo "🔧 Configuring Vault to trust Keycloak (Realm: $REALM_NAME)..."

if ! kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
  vault write "auth/${OIDC_PATH}/config" \
    oidc_discovery_url="$KEYCLOAK_DISCOVERY_URL" \
    oidc_client_id="$OIDC_CLIENT_ID" \
    oidc_client_secret="$OIDC_CLIENT_SECRET" \
    default_role="$ROLE_NAME"; then

  echo "⚠️ First attempt failed. Retrying after 5s..."
  sleep 5


    echo "🔧 Configuring Vault to trust Keycloak via $VAULT_ADDR..."
  # Retry once
  kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
    env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
    vault write "auth/${OIDC_PATH}/config" \
      oidc_discovery_url="$KEYCLOAK_DISCOVERY_URL" \
      oidc_client_id="$OIDC_CLIENT_ID" \
      oidc_client_secret="$OIDC_CLIENT_SECRET" \
      default_role="$ROLE_NAME" || {
        echo "❌ Final failure configuring Vault OIDC config"
        exit 1
      }
fi

  # Retry once
  kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
    env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
    vault write "auth/${OIDC_PATH}/config" \
      oidc_discovery_url="$KEYCLOAK_DISCOVERY_URL" \
      oidc_client_id="$OIDC_CLIENT_ID" \
      oidc_client_secret="$OIDC_CLIENT_SECRET" \
      default_role="$ROLE_NAME" || {
        echo "❌ Final failure configuring Vault OIDC config"
        exit 1
      }
fi
echo "🔍 Verifying OIDC configuration..."
  kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
    env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
    vault read auth/oidc/config || echo "No existing OIDC config found"
  exit 1
fi

# 🛡️ Create Vault Role for Keycloak Users
echo "📋 OIDC Role '$ROLE_NAME':"
kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
  vault read auth/oidc/role/$ROLE_NAME || {
    echo "⚠️ Failed to read role — it may not have been created properly."
    exit 1
}

# Create Certificate Resource (via mkcert-based Issuer)
echo "🔒 Configuring Vault TLS Certificate with mkcert issuer..."
#!/bin/bash

set -euo pipefail

echo "🔒 Configuring Vault TLS Certificate with mkcert issuer..."

# --- Cleanup previous attempts ---
echo "🧹 Cleaning up old CertificateRequests, Secrets, and Certificates..."
kubectl delete certificaterequest -n vault --all --ignore-not-found=true
kubectl delete secret vault-tls -n vault --ignore-not-found=true
kubectl delete certificate vault-tls -n vault --ignore-not-found=true
kubectl delete ingress vault-ingress -n vault --ignore-not-found=true

# --- Create Certificate YAML ---
VAULT_TLS_YAML="./bootstrap/addon-configs/vault/vault-tls.yaml"
mkdir -p "$(dirname "$VAULT_TLS_YAML")"
cat > "$VAULT_TLS_YAML" <<EOF
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: mkcert-cluster-issuer
spec:
  ca:
    secretName: mkcert-root-ca
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: vault-tls
  namespace: vault
spec:
  secretName: vault-tls
  duration: 8760h  # 1 year
  renewBefore: 360h
  commonName: vault.helix
  dnsNames:
    - vault.helix
  issuerRef:
    name: mkcert-cluster-issuer
    kind: ClusterIssuer
    group: cert-manager.io
EOF

# --- Apply Certificate ---
kubectl apply -f "$VAULT_TLS_YAML"
echo "✅ Certificate and ClusterIssuer applied."

echo "⏳ Waiting for TLS certificate 'vault-tls' to be issued by cert-manager..."

timeout=120   # max 2 minutes
elapsed=0
interval=5

while true; do
  status=$(kubectl get certificate vault-tls -n vault -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}")
  reason=$(kubectl get certificate vault-tls -n vault -o jsonpath="{.status.conditions[?(@.type=='Ready')].reason}")

  if [[ "$status" == "True" ]]; then
    echo "✅ Certificate issued successfully."
    break
  elif [[ "$reason" == "Failed" ]]; then
    echo "❌ Certificate issuance failed. Reason: $reason"
    kubectl describe certificate vault-tls -n vault
    exit 1
  fi

  if (( elapsed >= timeout )); then
    echo "❌ Timeout waiting for TLS certificate to be ready."
    kubectl describe certificate vault-tls -n vault
    exit 1
  fi

  echo "🔄 Waiting... ($elapsed/${timeout}s)"
  sleep $interval
  ((elapsed+=interval))
done

# --- Set up Ingress YAML ---
VAULT_INGRESS_YAML="./bootstrap/addon-configs/vault/vault-ingress.yaml"
cat > "$VAULT_INGRESS_YAML" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vault-ingress
  namespace: vault
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      traefik.ingress.kubernetes.io/router.tls: "true"
      traefik.ingress.kubernetes.io/service.serversscheme: "http"

spec:
  rules:
    - host: vault.helix
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: vault
                port:
                  number: 8200
  tls:
    - hosts:
        - vault.helix
      secretName: vault-tls
EOF

# --- Apply Ingress ---
kubectl apply -f "$VAULT_INGRESS_YAML"
echo "🌐 Vault Ingress configured at: https://vault.helix"

# --- Final check ---
kubectl get ingress -n vault
kubectl describe certificate vault-tls -n vault

# 📝 Final output
echo ""
echo "✅ Vault is now configured to trust Keycloak's '$REALM_NAME' realm."
echo "🌐 Login URL: https://vault.helix/ui/vault/auth/oidc"
echo ""
echo "🔧 Next steps:"
echo "   1. Ensure Keycloak client '$OIDC_CLIENT_ID' exists in realm '$REALM_NAME'"
echo "   2. Configure client redirect URI: https://vault.helix/ui/vault/auth/oidc/oidc/callback"
echo "   3. Set client secret to: $OIDC_CLIENT_SECRET"