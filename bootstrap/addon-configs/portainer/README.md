
Exactly, Angel — you're spot on. You're building something *modular*, *maintainable*, and *scriptable* — the Sherlock way. Here’s how to structure it cleanly:

---

## 🧠 Strategy

You want each service (like Portainer) to have:

1. Its own config (`.env`-style for clarity)
2. A deploy script (like you already have)
3. A **config hook function** (per-service customization)

And you want the main bootstrap script (or post-install hook) to *source a `config.sh`* and run relevant pre/post logic.

---

## 🧾 Example: `configs/portainer/portainer.env`

```dotenv
# Human-readable display
DISPLAY="🧱 Portainer (Docker UI)"

# Service name + namespace
SERVICE=portainer
NAMESPACE=portainer

# Network
PORT=9000
INGRESS_HOST=portainer.helix

# Auth
AUTH=true
OIDC_CLIENT_ID=portainer
OIDC_ISSUER=https://keycloak.helix/realms/helix
```

---

## 🔧 Example: `utils/core/config.sh`

```bash
# utils/core/config.sh

configure_oidc_for_portainer() {
  echo "🔐 Configuring OIDC for Portainer with Keycloak..."

  local host="https://keycloak.helix"
  local realm="helix"
  local admin_user="admin"
  local admin_pass="your-secret"

  # Get access token from Keycloak
  local token
  token=$(curl -s -X POST "$host/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$admin_user" -d "password=$admin_pass" \
    -d "grant_type=password" -d "client_id=admin-cli" | jq -r .access_token)

  # Create client if not already there
  curl -s -X POST "$host/admin/realms/$realm/clients" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{
      \"clientId\": \"portainer\",
      \"enabled\": true,
      \"redirectUris\": [\"https://portainer.helix/*\"],
      \"protocol\": \"openid-connect\",
      \"publicClient\": false,
      \"standardFlowEnabled\": true
    }" || echo "⚠️ Possibly already created. Continuing..."

  echo "✅ OIDC client registered in Keycloak for Portainer"
}
```

---

## 🧰 Adjusted `02_portainer-bootstrap.sh`

```bash
#!/bin/bash
# bootstrap/02_portainer-bootstrap.sh

source ./utils/core/config.sh
source ./configs/portainer/portainer.env

start_portainer_spinner() {
  local frames=("📦☁️" "🛰️📦" "📦🧭" "🚀📦" "📦🌍")
  local i=0
  while true; do
    printf "\r🌀 Deploying Portainer... ${frames[i]} "
    i=$(( (i + 1 ) % ${#frames[@]} ))
    sleep 0.5
  done
}

echo "🚀 Deploying $DISPLAY..."

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

start_portainer_spinner & SPINNER_PID=$!

# 📦 Helm repo
REPO_NAME="portainer"
REPO_URL="https://portainer.github.io/k8s/"
helm repo add "$REPO_NAME" "$REPO_URL" 2>/dev/null || true
helm repo update

# 🔐 Run OIDC Config Hook
configure_oidc_for_portainer

# 🚀 Install via Helm
helm upgrade --install portainer portainer/portainer \
  --namespace "$NAMESPACE" \
  --set service.type=NodePort \
  --set service.nodePort="$PORT" \
  --set ingress.enabled=false \
  --set persistence.enabled=true \
  --set persistence.size=1Gi \
  --set persistence.storageClass=local-path

# ⛔ Stop spinner
kill "$SPINNER_PID" >/dev/null 2>&1 || true
wait "$SPINNER_PID" 2>/dev/null || true
echo ""

# 🌐 Ingress (if defined)
INGRESS_FILE="./configs/portainer/portainer-ingress.yaml"
[[ -f "$INGRESS_FILE" ]] && {
  echo "🌐 Applying Portainer Ingress..."
  kubectl apply -f "$INGRESS_FILE"
}

echo ""
echo "🧭 $DISPLAY deployed at: https://$INGRESS_HOST"
```

---

## 🧬 Summary of Structure

```bash
bootstrap/
├── 02_portainer-bootstrap.sh
├── utils/
│   └── config.sh
├── configs/
│   └── portainer/
│       ├── portainer.env
│       └── portainer-ingress.yaml
```

---

## 💡 Future-Proofing

Now you can add a new service like `vault`, `keycloak`, or even `mlflow`, and just:

1. Drop a `vault.env`
2. Add an Ingress YAML
3. Extend `config.sh` with a function `configure_oidc_for_vault`

All your logic stays clean, modular, and testable.

---

Would you like me to generate the `vault.env`, ingress, and OIDC script functions for Vault next?
















./08-bootstrap-tls-trust.sh portainer --namespace portainer --resource-type deployment --resource-name portainer --ingress-name portainer-ingress --port 9000

kubectl rollout restart deployment portainer --namespace portainer

kubectl wait --namespace portainer   --for=condition=Ready pod -l app.kubernetes.io/name=portainer   --timeout=300s




kubectl apply -f ./configs/traefik-dashboard/traefik-dashboard-ingress.yaml
kubectl apply -f ./configs/traefik-dashboard/traefik-redirect-middleware.yaml
kubectl rollout restart deployment traefik --namespace kube-system
kubectl wait --namespace kube-system \
  --for=condition=Ready pod -l app.kubernetes.io/name=traefik \
  --timeout=300s




./08-bootstrap-tls-trust.sh traefik \
  --namespace kube-system \
  --resource-type deployment \
  --resource-name traefik \
  --ingress-name traefik-ingress \
  --port 8080




kubectl rollout restart deployment traefik --namespace kube-system

kubectl wait --namespace kube-system   --for=condition=Ready pod -l app.kubernetes.io/name=traefik   --timeout=300s




