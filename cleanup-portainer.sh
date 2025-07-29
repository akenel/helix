#!/usr/bin/env bash
# 🧹 Clean up existing Portainer installation

echo "🧹 Cleaning up existing Portainer installation..."

# Uninstall Helm release if it exists
if helm list -n portainer | grep -q "my-portainer\|portainer"; then
    echo "🗑️ Uninstalling existing Portainer Helm release..."
    helm uninstall my-portainer -n portainer 2>/dev/null || true
    helm uninstall portainer -n portainer 2>/dev/null || true
else
    echo "ℹ️ No Portainer Helm release found"
fi

# Delete namespace
if kubectl get namespace portainer &>/dev/null; then
    echo "🗑️ Deleting Portainer namespace..."
    kubectl delete namespace portainer --wait=true
else
    echo "ℹ️ Portainer namespace doesn't exist"
fi

# Clean up any PVCs that might be stuck
echo "🧽 Cleaning up any remaining PVCs..."
kubectl delete pvc -l app.kubernetes.io/name=portainer --all-namespaces 2>/dev/null || true

echo "✅ Cleanup complete! Ready for fresh installation."
