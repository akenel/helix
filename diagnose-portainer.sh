#!/usr/bin/env bash
# 🔍 Portainer Diagnostic Script

echo "🔍 Portainer Diagnostic Check"
echo "============================="

# Check namespace
echo "📦 Namespace status:"
if kubectl get namespace portainer &>/dev/null; then
    echo "✅ Namespace 'portainer' exists"
    kubectl get namespace portainer
else
    echo "❌ Namespace 'portainer' does not exist"
fi

echo ""

# Check Helm releases
echo "📋 Helm releases:"
if helm list -n portainer 2>/dev/null | grep -q .; then
    helm list -n portainer
else
    echo "❌ No Helm releases found in portainer namespace"
fi

echo ""

# Check all resources in portainer namespace
echo "🔍 All resources in portainer namespace:"
kubectl get all -n portainer 2>/dev/null || echo "❌ No resources found in portainer namespace"

echo ""

# Check events in portainer namespace
echo "📜 Recent events in portainer namespace:"
kubectl get events -n portainer --sort-by='.firstTimestamp' 2>/dev/null || echo "❌ No events found"

echo ""

# Check storage classes
echo "💾 Available storage classes:"
kubectl get storageclass

echo ""

# Check if there are any PVCs
echo "💿 Persistent Volume Claims:"
kubectl get pvc -n portainer 2>/dev/null || echo "❌ No PVCs found in portainer namespace"

echo ""

# Show nodes status
echo "🖥️ Node status:"
kubectl get nodes

echo ""
echo "🔍 Diagnostic complete!"
