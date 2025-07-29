#!/bin/bash

set -euo pipefail

trap '[[ -n "${KUBECONFIG_TEMP:-}" ]] && rm -f "$KUBECONFIG_TEMP"' EXIT INT TERM

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🎩 69 - Helix Cluster Royal Health Check
# 🔍 Platform Integrity, Identity & TLS Inspection
# 👑 By Angel & Sherlock Holmes
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
echo "🔐 Helix Platform Cluster Health Audit"
echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"

# Kubeconfig override
export KUBECONFIG="${KUBECONFIG:-$HOME/.helix/kubeconfig.yaml}"

# 🧪 Check cluster access
kubectl config use-context k3d-helix >/dev/null 2>&1 || {
  echo -e "\e[31m❌ Unable to connect to Kubernetes API. Check kubeconfig or cluster status.\e[0m"
  exit 1
}

# 📦 Dependency checks
for bin in curl jq docker ip date tee vault; do
  command -v "$bin" >/dev/null || {
    echo "❗ Required binary '$bin' missing. Aborting."
    exit 1
  }
done

# 📜 Summary Logs
LOG_DIR="logs/$(date +%Y%m%d)"
mkdir -p "$LOG_DIR"
SUMMARY_LOG="$LOG_DIR/helix_deployment_summary.log"
touch "$SUMMARY_LOG"

log_summary() {
  local type=$1 msg=$2 ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[${ts}] [${type}] $msg" | tee -a "$SUMMARY_LOG"
}

# 🗺️ Geo & Environment Check
HOST_IP=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
DOCKER_VER=$(docker version --format '{{.Client.Version}}/{{.Server.Version}}' 2>/dev/null || echo "N/A")
LINUX_INFO=$(uname -srm)

CITY="Unknown"; REGION="Unknown"; COUNTRY="Unknown"; TEMP="N/A"; WIND="N/A"
LOCATION_JSON=$(curl -s https://ipapi.co/json/)
if [[ -n "$LOCATION_JSON" ]]; then
  CITY=$(echo "$LOCATION_JSON" | jq -r '.city')
  REGION=$(echo "$LOCATION_JSON" | jq -r '.region')
  COUNTRY=$(echo "$LOCATION_JSON" | jq -r '.country_name')
  LAT=$(echo "$LOCATION_JSON" | jq -r '.latitude')
  LON=$(echo "$LOCATION_JSON" | jq -r '.longitude')
  if [[ "$LAT" != "0" && "$LON" != "0" ]]; then
    WEATHER_JSON=$(curl -s "https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}&current_weather=true")
    TEMP=$(echo "$WEATHER_JSON" | jq -r '.current_weather.temperature')
    WIND=$(echo "$WEATHER_JSON" | jq -r '.current_weather.windspeed')
  fi
fi

# 📊 Environment Summary
log_summary INFO "Geo: ${CITY}, ${REGION}, ${COUNTRY}"
log_summary INFO "Weather: ${TEMP}°C, Wind ${WIND} km/h"
log_summary INFO "Host IP: $HOST_IP"
log_summary INFO "Docker: $DOCKER_VER"
log_summary INFO "OS: $LINUX_INFO"

echo -e "\n🩺 Cluster Environment at $(date)"
echo "📍 Location: $CITY, $REGION, $COUNTRY"
echo "🌤️ Weather: ${TEMP}°C, Wind ${WIND} km/h"
echo "🐧 OS: $LINUX_INFO • 🐳 Docker: $DOCKER_VER"
echo "---------------------------------------------"

# 🌐 Cluster Status
echo "🔍 Connected Clusters:"
k3d cluster list | awk 'NR>1 {print "🟢 " $1}'
echo ""

# 📡 Select Cluster
read -p "🤖 Cluster name to inspect [default: helix]: " CLUSTER_NAME
CLUSTER_NAME=${CLUSTER_NAME:-helix}
if ! k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo -e "\e[31m❌ Cluster '$CLUSTER_NAME' not found.\e[0m"
  exit 1
fi

KUBECONFIG_TEMP=$(mktemp)
k3d kubeconfig get "$CLUSTER_NAME" > "$KUBECONFIG_TEMP"
sed -i 's|host.docker.internal|127.0.0.1|g' "$KUBECONFIG_TEMP"
export KUBECONFIG="$KUBECONFIG_TEMP"

# 🔄 Kubeconfig Patching
kubectl config set-cluster "k3d-${CLUSTER_NAME}" --server="https://127.0.0.1:6550" &>/dev/null
kubectl config use-context "k3d-${CLUSTER_NAME}" &>/dev/null

echo "✅ Using context: k3d-${CLUSTER_NAME} (API patched to 127.0.0.1)"
kubectl cluster-info || { echo "❌ Cluster unreachable"; exit 1; }

# 🧩 Node & Pod Health
echo -e "\n🧱 Nodes"
kubectl get nodes -o wide

echo -e "\n📦 Pods by Namespace"
kubectl get pods --all-namespaces

echo -e "\n🚨 Non-Ready Pods"
kubectl get pods --all-namespaces --field-selector=status.phase!=Running --no-headers || echo "✅ All pods running"

# 🧪 Cert-Manager Status
echo -e "\n🔐 Cert-Manager"
kubectl get pods -n cert-manager || echo "❌ Cert-manager not found"

# 👁️ Identity System Check: Keycloak
echo -e "\n👤 Keycloak Identity Status"
if kubectl get pods -n identity | grep -q keycloak; then
  KC_POD=$(kubectl get pods -n identity -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')
  echo "🟢 Keycloak Pod: $KC_POD"
  echo "🔐 Checking realm 'helix'..."
  kubectl exec -n identity "$KC_POD" -- kcadm.sh config credentials \
    --server http://localhost:8080 --realm master \
    --user admin --password admin &>/dev/null \
    && echo "✅ KCADM authenticated" \
    && kubectl exec -n identity "$KC_POD" -- kcadm.sh get realms/helix || echo "❌ Realm not found"
else
  echo "❌ Keycloak pod missing in 'identity' namespace"
fi

# 🗝️ Vault Status
echo -e "\n🔐 Vault Status"
if command -v vault &>/dev/null && [[ -n "${VAULT_ADDR:-}" ]]; then
  vault status || echo "⚠️ Vault CLI failed"
else
  echo "⚠️ Vault not configured or CLI missing"
fi

# 📍 Services Summary
echo -e "\n🧭 Ingress Points"
echo "🔗 https://portainer.helix"
echo "🔗 https://keycloak.helix"
echo "🔗 https://vault.helix"
echo "🔗 https://adminer.helix"
echo "🔗 https://traefik.helix/dashboard"

# 📊 Final Scorecard
echo -e "\n📋 Cluster Scorecard"
echo "Namespaces:  $(kubectl get ns --no-headers | wc -l)"
echo "Nodes:       $(kubectl get nodes --no-headers | wc -l)"
echo "Pods:        $(kubectl get pods --all-namespaces --no-headers | wc -l)"
echo "Deployments: $(kubectl get deployments --all-namespaces --no-headers | wc -l)"

# 🥋 Chuck Norris for Closure
JOKE=$(curl -s https://api.chucknorris.io/jokes/random | jq -r '.value')
echo -e "\n🥋 Completed Live-Health Chuck: $JOKE"

echo -e "\n✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
echo "✅ Cluster Audit Complete — Long live Helix!"
echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
