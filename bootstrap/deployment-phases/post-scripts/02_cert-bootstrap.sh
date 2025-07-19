#!/bin/bash
# ./bootstrap/02_cert-bootstrap.sh
set -e

echo "🔐 Helix Certificate Bootstrap"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "SCRIPT_DIR $SCRIPT_DIR"
source "utils/bootstrap/config.sh" 
# Show available clusters
CLUSTERS=($(k3d cluster list | awk 'NR>1 {print $1}'))

echo ""
echo "🔍 Available k3d clusters:"
for cl in "${CLUSTERS[@]}"; do echo "- $cl"; done
echo ""

# Suggest default if only one cluster
DEFAULT_CLUSTER="helix"
if [ ${#CLUSTERS[@]} -eq 1 ]; then
  DEFAULT_CLUSTER="${CLUSTERS[0]}"
fi

# Prompt user
# read -p "🌠 Enter cluster name [default: ${DEFAULT_CLUSTER}]: " CLUSTER
CLUSTER=${CLUSTER:-$DEFAULT_CLUSTER}
DOMAIN="helix"
WILDCARD="*.${DOMAIN}"
SECRET_NAME="${CLUSTER}-tls"
NAMESPACE="cert-manager"
echo ""
echo "🌍 Domain will be: ${WILDCARD}"
echo "🔑 Kubernetes TLS Secret: ${SECRET_NAME}"
echo ""

# Ensure registry is running
if ! docker ps --format '{{.Names}}' | grep -q "k3d-${DOMAIN}-registry"; then
  echo "⚠️  Registry 'k3d-${DOMAIN}-registry' not found. Please create registry first."
  exit 1
else
  echo "✅ Registry present."
fi
VALID_URL=$(kubectl config view -o=jsonpath='{.clusters[?(@.name=="k3d-helix")].cluster.server}')
if [[ "$VALID_URL" != https://127.0.0.1:* ]]; then
  echo "❌ kubeconfig server URL ($VALID_URL) is invalid. Fixing..."
  kubectl config set-cluster k3d-helix --server="https://127.0.0.1:6550"
  echo "✅ kubeconfig fixed."
fi

# Install cert-manager if missing
if ! kubectl get namespace cert-manager &>/dev/null; then
  echo "📥 Installing cert-manager..."
 
  REPO_NAME="cert-manager"
  REPO_URL="https://charts.jetstack.io"
  if ! helm repo list | grep -q "$REPO_NAME"; then
    echo "📦 Adding Helm repository: $REPO_NAME"
    helm repo add "$REPO_NAME" "$REPO_URL"
  else
    echo "📦 Helm repository '$REPO_NAME' already exists. Skipping 'helm repo add'."
  fi

  helm install cert-manager cert-manager/cert-manager \
    --version 1.18.2 \
    --set installCRDs=true \
    --insecure-skip-tls-verify \
    --namespace=$NAMESPACE --create-namespace \
    --set global.validationFailureAction=Ignore \
    --disable-openapi-validation
  echo "⏳ Waiting for cert-manager deployment..."
  sleep 2
  kubectl rollout status deployment/$NAMESPACE -n $NAMESPACE 
else
  echo "✅ cert-manager already installed."
fi

# Install mkcert if needed
# ... (previous script content) ...

# Install mkcert if needed
if ! command -v mkcert &>/dev/null; then
  echo "📥 Installing mkcert..."
  sudo apt-get update
  sudo apt-get install -y libnss3-tools
  curl -JLO "https://github.com/FiloSottile/mkcert/releases/latest/download/mkcert-v1.4.5-linux-amd64"
  chmod +x mkcert-v1.4.5-linux-amd64
  sudo mv mkcert-v1.4.5-linux-amd64 /usr/local/bin/mkcert
  mkcert -install
fi

# File paths
CERTFILE="${CLUSTER}-tls.crt"
KEYFILE="${CLUSTER}-tls.key"
# Fix: BASHSOURCE changed to BASH_SOURCE
# CERTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/support" && pwd)"

CERTDIR="$(pwd)"
# KUBECONFIG_DIR="$HOME/.helix"
# KUBECONFIG_FILE="$KUBECONFIG_DIR/kubeconfig.yaml"
# USER_NAME="admin@helix"
# CONTEXT_NAME="helix"
# CLUSTER_NAME="helix"


# Recreate TLS secret if it exists
if kubectl get secret "$SECRET_NAME" &>/dev/null; then
  echo "⚠️  TLS secret '$SECRET_NAME' already exists."
  read -p "🔁 Overwrite it? (y/N): " ow
  if [[ "$ow" != "y" ]]; then
    echo "❌ Operation cancelled."
    exit 0
  fi
  kubectl delete secret "$SECRET_NAME"
fi

# Generate certs
# mkcert will place the files in ../certs relative to where the script is run (bootstrap dir)
mkcert -cert-file "${CERTDIR}/${CERTFILE}" -key-file "${CERTDIR}/${KEYFILE}" "$WILDCARD" "localhost"

echo "✅ MKCERTs located in $CERTDIR with names generated: $CERTFILE, $KEYFILE"

# Fix: Use CERTFILE and KEYFILE (consistent with definition)
# Fix: Added missing backslash at the end of the line
kubectl create secret tls "$SECRET_NAME" \
  --cert="${CERTDIR}/${CERTFILE}" \
  --key="${CERTDIR}/${KEYFILE}" \
&& echo "✅ TLS secret '${SECRET_NAME}' created." # Use && for conditional success message

# Offer to update Windows hosts file via WSL
# ... (rest of your script) ...

# Offer to update Windows hosts file via WSL
echo ""
if [ -t 0 ]; then
  read -t 10 -p "🖥️  Inject 127.0.0.1 entries into Windows hosts file? (y/N): " hosts || true
fi

if [[ "$hosts" == "y" ]]; then
  echo -e "127.0.0.1 ${DOMAIN}\n127.0.0.1 ${CLUSTER}.${DOMAIN}" | \
    sudo tee -a /mnt/c/Windows/System32/drivers/etc/hosts > /dev/null
  echo "✅ Hosts file updated for Windows."
fi

echo ""
echo "✅ Now you can deploy services under *.${DOMAIN}:"
echo "🎯 for HTTPS URLs add etc/hosts entries as follows, e.g.:"
echo "127.0.0.1 keycloak.${DOMAIN}"
echo "127.0.0.1 portainer.${DOMAIN}"
echo "127.0.0.1 adminer.${DOMAIN}"
echo "127.0.0.1 vault.${DOMAIN}"
echo "127.0.0.1 traefik.${DOMAIN}"
# Chuck Norris Bonus
CHUCKS=(
  "When Chuck Norris generates a cert, the browser trusts it automatically."
  "kubectl get secret TLS? No need — Chuck keeps it safe by stare alone."
  "mkcert works faster than light when Chuck checks its timestamp."
)
echo "😂 Chuck Norris says: ${CHUCKS[$RANDOM % ${#CHUCKS[@]}]}"
echo ""