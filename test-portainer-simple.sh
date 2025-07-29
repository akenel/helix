#!/usr/bin/env bash
# 🚀 Quick Portainer Installation Test
set -euo pipefail

echo "🚀 Quick Portainer Test Installation"
echo "===================================="

# Ensure we're in the right directory
cd "$(dirname "$0")/../../.."
ROOT_DIR="$(pwd)"
echo "📂 Working from: $ROOT_DIR"

# Add Portainer repo if needed
echo "📦 Ensuring Portainer Helm repo..."
if ! helm repo list | grep -q portainer; then
    helm repo add portainer https://portainer.github.io/k8s/
fi
helm repo update portainer

# Check if already installed
echo "🔍 Checking existing installation..."
if helm list -n portainer | grep -q my-portainer; then
    echo "⚠️ Portainer already installed. Uninstalling first..."
    helm uninstall my-portainer -n portainer
    kubectl delete namespace portainer --ignore-not-found=true
    echo "🗑️ Cleaned up existing installation"
fi

# Install Portainer
echo "🚀 Installing Portainer..."
kubectl create namespace portainer --dry-run=client -o yaml | kubectl apply -f -

helm install my-portainer portainer/portainer \
  --namespace portainer \
  --version 1.0.69 \
  --set persistence.enabled=true \
  --set persistence.size=10Gi \
  --set persistence.storageClass="" \
  --set agent.enabled=true \
  --atomic \
  --timeout 5m

echo ""
echo "✅ Installation completed!"

# Wait for deployment
echo "⏳ Waiting for Portainer to be ready..."
kubectl wait --for=condition=Available deployment/my-portainer -n portainer --timeout=300s

# Show status
echo "📊 Portainer Status:"
kubectl get pods,svc -n portainer

# Get access info
NODE_PORT=$(kubectl get svc my-portainer -n portainer -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
echo ""
echo "🌐 Access Portainer at: https://localhost:$NODE_PORT"
echo "🔐 Set admin password on first login"
