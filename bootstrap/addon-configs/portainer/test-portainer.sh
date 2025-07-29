#!/usr/bin/env bash
# 🧪 Test Portainer Installation
set -euo pipefail

echo "🧪 Testing Portainer Installation"
echo "================================="

# Check if Portainer is deployed
echo "📡 Checking Portainer deployment..."
if ! kubectl get deployment my-portainer -n portainer &>/dev/null; then
    echo "❌ Portainer deployment not found"
    exit 1
fi

# Check deployment status
READY=$(kubectl get deployment my-portainer -n portainer -o jsonpath='{.status.readyReplicas}')
DESIRED=$(kubectl get deployment my-portainer -n portainer -o jsonpath='{.spec.replicas}')

echo "✅ Portainer deployment found: $READY/$DESIRED replicas ready"

# Check pods
echo "🏃 Checking Portainer pods..."
kubectl get pods -n portainer -l app.kubernetes.io/name=portainer

# Check service
echo "🌐 Checking Portainer service..."
kubectl get svc my-portainer -n portainer

# Get access URL
NODE_PORT=$(kubectl get svc my-portainer -n portainer -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo ""
echo "🚀 Portainer Access Information:"
echo "  Web UI: https://$NODE_IP:$NODE_PORT"
echo "  Local: https://localhost:$NODE_PORT"
echo ""
echo "🔐 First-time setup:"
echo "  1. Open the web UI"
echo "  2. Create an admin password"
echo "  3. Select 'Get Started' to manage the local Kubernetes cluster"
echo ""
echo "✅ Portainer test completed!"
