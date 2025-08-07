#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR
# bootstrap\02_portainer-bootstrap.sh
start_portainer_spinner() {
  local frames=("📦☁️" "🛰️📦" "📦🧭" "🚀📦" "📦🌍")
  local i=0
  while true; do
    printf "\r🌀 Deploying Portainer... ${frames[i]} "
    i=$(( (i + 1) % ${#frames[@]} ))
    sleep 0.5
  done
}

echo "🚀 Deploying Portainer dashboard... please wait"
kubectl create namespace portainer --dry-run=client -o yaml | kubectl apply -f -
start_portainer_spinner & SPINNER_PID=$!

    # In 03-vault-bootstrap-unseal.sh
    REPO_NAME="portainer"
    REPO_URL="https://portainer.github.io/k8s/"
    if ! helm repo list | grep -q "$REPO_NAME"; then
      echo "📦 Adding Helm repository: $REPO_NAME"
      helm repo add "$REPO_NAME" "$REPO_URL"
    else
      echo "📦 Helm repository '$REPO_NAME' already exists. Skipping 'helm repo add'."
    fi

helm repo update

helm install portainer portainer/portainer \
  --namespace portainer \
  --set service.type=NodePort \
  --set service.nodePort=30069 \
  --set ingress.enabled=false \
  --set persistence.enabled=true \
  --set persistence.size=1Gi \
  --set persistence.storageClass=local-path

kill "$SPINNER_PID" >/dev/null 2>&1 || true
wait "$SPINNER_PID" 2>/dev/null || true
echo ""

INGRESS_FILE="./configs/portainer/portainer-ingress.yaml"
echo "🌐 Applying Portainer Ingress configurations..."
kubectl apply -f "$INGRESS_FILE"

echo ""
echo "🧭 Portainer deployed.  Access it at: http://localhost:30069"
echo ""

URL="http://localhost:30069"
echo "🌐 Portainer dashboard at $URL"
# if command -v xdg-open &>/dev/null; then
#   xdg-open "$URL" >/dev/null 2>&1
# elif command -v open &>/dev/null; then
#   open "$URL" >/dev/null 2>&1
# elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
#   start "$URL"
# else
#   echo "ℹ️ Could not auto-open the browser. Please visit: $URL"
# fi
