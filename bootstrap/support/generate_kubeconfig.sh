#!/bin/bash

# ──────────────────────────────────────────────────────────────
# 🚀 HELIX TLS + kubeconfig + RBAC Bootstrapping Script
# Author: Sherlock Holmes 🕵️‍♂️
# Purpose: Fully configure kubectl + TLS for k3d with mkcert
# Location: bootstrap/certs/generate-helix-kubeconfig.sh
# ──────────────────────────────────────────────────────────────

set -euo pipefail

CERT_DIR="$(pwd)"
KUBECONFIG_DIR="$HOME/.helix"
KUBECONFIG_FILE="$KUBECONFIG_DIR/kubeconfig.yaml"
USER_NAME="admin@helix"
CONTEXT_NAME="helix"
CLUSTER_NAME="helix"

echo "🔧 Bootstrapping kubeconfig setup from cert directory: $CERT_DIR"
# 🕵️ Helper: Show current kubectl context info
show_kubectl_context() {
  echo ""
  echo "🔍 Current kubectl context info:"
  echo "   🔸 KUBECONFIG: ${KUBECONFIG:-$HOME/.kube/config}"
  echo "   🔸 Current context: $(kubectl config current-context 2>/dev/null || echo "none")"
  echo "   🔸 Cluster: $(kubectl config view --minify -o jsonpath='{.clusters[0].name}' 2>/dev/null || echo "n/a")"
  echo "   🔸 Server:  $(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo "n/a")"
  echo "   🔸 User:    $(kubectl config view --minify -o jsonpath='{.users[0].name}' 2>/dev/null || echo "n/a")"
  echo ""
}

mkdir -p "$KUBECONFIG_DIR"

# Step 1: Generate certs if missing
if [[ ! -f "$CERT_DIR/helix.crt" || ! -f "$CERT_DIR/helix.key" ]]; then
  echo "🔐 No TLS certs found – generating with mkcert..."
  mkcert -cert-file "$CERT_DIR/helix.crt" -key-file "$CERT_DIR/helix.key" 127.0.0.1 localhost
else
  echo "🔐 TLS certs already exist – skipping mkcert generation."
fi

# Step 2: Encode certs for kubeconfig
CA_DATA=$(base64 -w 0 "$CERT_DIR/helix.crt")
CLIENT_CERT_DATA=$(base64 -w 0 "$CERT_DIR/helix.crt")
CLIENT_KEY_DATA=$(base64 -w 0 "$CERT_DIR/helix.key")

show_kubectl_context

echo "🧬 Writing kubeconfig to: $KUBECONFIG_FILE"
cat > "$KUBECONFIG_FILE" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: $CLUSTER_NAME
  cluster:
    server: https://127.0.0.1:6550
    certificate-authority-data: $CA_DATA

users:
- name: $USER_NAME
  user:
    client-certificate-data: $CLIENT_CERT_DATA
    client-key-data: $CLIENT_KEY_DATA

contexts:
- name: $CONTEXT_NAME
  context:
    cluster: $CLUSTER_NAME
    user: $USER_NAME

current-context: $CONTEXT_NAME
EOF

# Step 3: Set context
export KUBECONFIG="$KUBECONFIG_FILE"
echo "✅ KUBECONFIG is now set to: $KUBECONFIG_FILE"
show_kubectl_context


echo "🕒 Waiting for Kubernetes API server to trust the mkcert CA..."

for i in {1..20}; do
  if kubectl get --raw=/apis/rbac.authorization.k8s.io/v1/clusterrolebindings &>/dev/null; then
    echo "✅ API server trusts mkcert CA — proceeding to create RBAC binding."
    break
  else
    echo "🔄 API still warming up TLS trust... ($i/20)"
    sleep 3
  fi
done





# Step 4: Grant admin RBAC if needed
echo "🔐 Checking for admin ClusterRoleBinding..."
if ! kubectl get clusterrolebinding helix-admin-binding >/dev/null 2>&1; then
  echo "🛡️  Creating ClusterRoleBinding for user '$USER_NAME'..."

  show_kubectl_context
  kubectl create clusterrolebinding helix-admin-binding \
    --clusterrole=cluster-admin \
    --user="$USER_NAME"

   show_kubectl_context 
else
show_kubectl_context
  echo "🛡️  ClusterRoleBinding 'helix-admin-binding' already exists."
fi
show_kubectl_context
# Step 5: Show comparison between kubeconfigs
echo ""
echo "📂 Kubeconfig Comparison:"
echo "   • Default:        ~/.kube/config"
echo "   • Custom Helix:   $KUBECONFIG_FILE"

echo ""
echo "🔎 Key ID Fingerprints:"
echo "   • ~/.kube/config (k3d default):"
grep "client-key-data" ~/.kube/config | head -n1 | awk '{print "     "substr($2,1,12) "..."}'

echo "   • ~/.helix/kubeconfig.yaml (helix):"
grep "client-key-data" "$KUBECONFIG_FILE" | head -n1 | awk '{print "     "substr($2,1,12) "..."}'

# Step 6: Final Sanity Check
echo ""
echo "🔍 Running sanity checks with kubectl..."
show_kubectl_context
kubectl get nodes
kubectl get namespaces
kubectl cluster-info
show_kubectl_context
# Step 7: Tips
echo ""
echo "🎯 To set this kubeconfig automatically, add to ~/.bashrc:"
echo "   export KUBECONFIG=$KUBECONFIG_FILE"
echo ""
echo "🧪 Top kubectl sanity commands:"
echo "   kubectl get nodes"
echo "   kubectl get pods -A"
echo "   kubectl describe pod <pod-name>"
echo "   kubectl logs <pod-name>"
echo ""
echo "✅ All done! TLS, context, and admin access are wired up."
