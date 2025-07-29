#!/usr/bin/env bash
# 🔍 Portainer Pre-flight Checks
set -euo pipefail

echo "🚁 Portainer Pre-flight Checks"
echo "================================"

# Check if cluster is running
echo "📡 Checking cluster connectivity..."
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Kubernetes cluster not accessible"
    echo "💡 Start cluster with: ./run.sh"
    exit 1
fi
echo "✅ Cluster is accessible"

# Check if Helm is available
echo "📦 Checking Helm..."
if ! command -v helm &>/dev/null; then
    echo "❌ Helm not found"
    exit 1
fi
echo "✅ Helm is available ($(helm version --template '{{.Version}}' 2>/dev/null || echo 'version check failed'))"

# Check if Portainer repo is added
echo "🗃️ Checking Portainer Helm repository..."
if ! helm repo list | grep -q "portainer"; then
    echo "⚠️ Portainer Helm repo not found. Adding it..."
    helm repo add portainer https://portainer.github.io/k8s/
    helm repo update
    echo "✅ Portainer Helm repo added"
else
    echo "✅ Portainer Helm repo is available"
    helm repo update portainer
fi

# Check if Portainer chart exists
echo "📋 Checking Portainer chart availability..."
if ! helm search repo portainer/portainer &>/dev/null; then
    echo "❌ Portainer chart not found"
    exit 1
fi
echo "✅ Portainer chart found: $(helm search repo portainer/portainer --output json | jq -r '.[0].version')"

# Check storage classes
echo "💾 Checking storage classes..."
STORAGE_CLASSES=$(kubectl get storageclass -o name | wc -l)
if [[ $STORAGE_CLASSES -eq 0 ]]; then
    echo "⚠️ No storage classes found"
else
    echo "✅ Found $STORAGE_CLASSES storage class(es):"
    kubectl get storageclass
fi

# Check if Portainer is already installed
echo "🔍 Checking existing Portainer installation..."
if kubectl get namespace portainer &>/dev/null; then
    echo "⚠️ Portainer namespace already exists"
    if helm list -n portainer | grep -q portainer; then
        echo "⚠️ Portainer Helm release already exists:"
        helm list -n portainer
        echo "💡 Use 'upgrade' action instead of 'install'"
    else
        echo "ℹ️ Namespace exists but no Helm release found"
    fi
else
    echo "✅ No existing Portainer installation found"
fi

# Show what will be installed
echo ""
echo "📝 Installation Summary:"
echo "  - Chart: portainer/portainer v1.0.69"
echo "  - Namespace: portainer (will be created)"
echo "  - Release Name: my-portainer"
echo "  - Values File: bootstrap/addon-configs/portainer/portainer-values.yaml"
echo "  - Service Type: NodePort"
echo "  - Web UI Port: 30777 (https://localhost:30777)"
echo ""
echo "✅ Pre-flight checks completed! Ready for installation."
