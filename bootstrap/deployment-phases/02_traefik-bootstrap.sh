#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR
# 🧱 bootstrap/02_traefik-bootstrap.sh
set -e
echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
echo "🚀 Traefik Bootstrap for HTTPs Dashboard 🧱"
echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
echo ""
echo "🔍 Available k3d clusters:"
k3d cluster list | awk 'NR>1 {print "🔥 " $1}'
echo ""
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
# read -p "🌠 Enter cluster name [default: helix]: " CLUSTER_INPUT
CLUSTER=${CLUSTER_INPUT:-helix}
NAMESPACE="${NAMESPACE:-kube-system}"
RELEASE="${RELEASE:-traefik-${CLUSTER}}"

echo -e "\n🐳 CLUSTER='$CLUSTER'"
echo -e "  - NAMESPACE='$NAMESPACE'"
echo -e "  - RELEASE='$RELEASE'"

traefik_spinner() {
  local frames=("🚦" "🔄" "🧭" "📊" "🚦")
  local i=0
  while true; do
    printf "\r🌀 Wiring Traefik Dashboard... ${frames[i]} "
    i=$(( (i + 1) % ${#frames[@]} ))
    sleep 0.5
  done
}

# ✅ 1. Launch in the Background
traefik_spinner & SPINNER_PID=$!
# ✅ 2. Apply Traefik Dashboard IngressRoute
# 🔍 Resolve base path safely
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="${SCRIPT_DIR}/../addon-configs/traefik-dashboard"
INGRESS_FILE="${ADDON_DIR}/traefik-dashboard-ingressroute.yaml"

# ✅ Safety check
if [[ ! -f "$INGRESS_FILE" ]]; then
  echo "❌ ERROR: File not found: $INGRESS_FILE"
  exit 1
fi

# ✅ Apply using absolute path
kubectl apply -f "$INGRESS_FILE"

kubectl rollout restart deployment traefik -n kube-system

kill "$SPINNER_PID" >/dev/null 2>&1 || true
wait "$SPINNER_PID" 2>/dev/null || true

echo ""
echo "\n✅ Success 🚀 Traefik Dashboard Ready 🧱\n"
