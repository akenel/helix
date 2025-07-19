#!/bin/bash
# bootstrap/05_adminer-bootstrap.sh
export KUBECONFIG="${KUBECONFIG:-/home/angel/.helix/kubeconfig.yaml}"
CONTEXT_NAME=$(kubectl config current-context 2>/dev/null || echo "")
if [[ -z "$CONTEXT_NAME" ]]; then
  echo "❌ No valid Kubernetes context found in kubeconfig ($KUBECONFIG)"
  exit 1
fi

echo "🔧 Using context: $CONTEXT_NAME"

# 🎨 Color codes
BRIGHT_GREEN='\033[1;32m'
NC='\033[0m' # No Color

# 🛠️ Configuration
NAMESPACE="database-ui"
RELEASE="adminer"
CHART="cetic/adminer"
VALUES="configs/adminer/adminer_values.yaml"
VERSION="0.2.1"
if [[ ! -f "$VALUES" ]]; then
  echo "❌ Adminer values file not found: $VALUES"
  exit 1
fi

# 🌀 Spinner
spin() {
  local pid=$!
  local delay=0.1
  local spinstr='|/-\'
  while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

echo "🚀 Installing Adminer..."

# 🧱 Add Helm repo
echo "📦 Adding Cetic Helm repository..."
helm repo add cetic https://cetic.github.io/helm-charts > /dev/null 2>&1 || echo "ℹ️  'cetic' repo already exists"
helm repo add bitnami https://charts.bitnami.com/bitnami > /dev/null 2>&1 || true

# 🔄 Update repos
echo "🔄 Updating Helm repositories..."
(helm repo update > /dev/null 2>&1) & spin
echo "✅ Repositories updated."

# 📥 Install Adminer
echo "📥 Deploying ${RELEASE} from ${CHART} into namespace '${NAMESPACE}'..."
trap "kill 0" EXIT
helm upgrade --install "$RELEASE" "$CHART" \
  --version "$VERSION" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f "$VALUES" \
  --wait --timeout 300s || {
    echo "❌ Adminer installation failed."
    exit 1
  }

# 🩺 Wait for rollout
echo "⏳ Waiting for Adminer rollout to complete..."
kubectl rollout status deployment "$RELEASE" -n "$NAMESPACE" --timeout=300s

echo -e "${BRIGHT_GREEN}✅ Adminer installed successfully in namespace '${NAMESPACE}'!${NC}"
 kubectl get svc "$RELEASE" -n "$NAMESPACE"
 kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=adminer

echo "URL=https://adminer.helix"
echo ""
echo "🌐 Adminer deployed.  Web database UI Secure URL: $URL "
echo ""