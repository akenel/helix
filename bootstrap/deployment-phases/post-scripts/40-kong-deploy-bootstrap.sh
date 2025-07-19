#!/bin/bash
set -euo pipefail

echo "🧨 Uninstalling old Kong release and cleaning up namespace..."

# 1. Uninstall Kong and delete namespace
helm uninstall kong -n kong >/dev/null 2>&1 || echo "⚠️ No existing kong release."
helm uninstall kong-dp -n kong >/dev/null 2>&1 || echo "⚠️ No existing kong-dp release."
kubectl delete ns kong --ignore-not-found=true
sleep 3

# 2. Delete *all* Kong CRDs
echo "🧹 Deleting Kong-related CRDs..."
kubectl get crd -o name | grep konghq | xargs -r kubectl delete --ignore-not-found
sleep 2

# Final pass: double check nothing reappeared
REMAINING_CRDS=$(kubectl get crd -o name | grep konghq || true)
if [[ -n "$REMAINING_CRDS" ]]; then
  echo "🔁 Final pass CRD deletion..."
  echo "$REMAINING_CRDS" | xargs -r kubectl delete --ignore-not-found
  sleep 2
fi

# 3. Namespace recreated after everything is clean
kubectl create ns kong --dry-run=client -o yaml | kubectl apply -f -

# 4. TLS Generation (certs go in ./certs/Kong)
mkdir -p certs/Kong
if [[ ! -f certs/Kong/kong.helix.pem ]]; then
  echo "🔐 Generating mkcert TLS cert for kong.helix"
  mkcert -cert-file certs/Kong/kong.helix.pem -key-file certs/Kong/kong.helix-key.pem kong.helix
else
  echo "✅ TLS certs already exist in certs/Kong"
fi

# 5. Create Secrets (use correct paths!)
echo "🔐 Creating Kong TLS secrets..."
kubectl -n kong create secret tls kong-proxy-mtls \
  --cert=certs/Kong/kong.helix.pem --key=certs/Kong/kong.helix-key.pem \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n kong create secret tls kong-admin-mtls \
  --cert=certs/Kong/kong.helix.pem --key=certs/Kong/kong.helix-key.pem \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n kong create secret generic kong-cluster-cert \
  --from-file=tls.crt=certs/Kong/kong.helix.pem \
  --from-file=tls.key=certs/Kong/kong.helix-key.pem \
  --dry-run=client -o yaml | kubectl apply -f -

# 6. Apply plugin configmap if it exists
[[ -f ./configs/kong/kong-plugin-oidc.yaml ]] && \
  kubectl apply -f ./configs/kong/kong-plugin-oidc.yaml || \
  echo "⚠️ No OIDC config map found — skipping."

# 7. Helm repo setup
helm repo add kong https://charts.konghq.com 2>/dev/null || true
helm repo update

# 8. Install Kong CRDs manually (separate from Helm)
echo "📦 Installing Kong CRDs manually..."
kubectl apply -f https://github.com/Kong/charts/raw/main/charts/kong/crds/custom-resource-definitions.yaml

# 9. Patch CRDs for Helm ownership
echo "🛡️ Patching Kong CRDs with Helm metadata..."
kubectl get crd -o name | grep konghq | while read -r crd; do
  kubectl annotate "$crd" \
    meta.helm.sh/release-name=kong \
    meta.helm.sh/release-namespace=kong --overwrite
  kubectl label "$crd" app.kubernetes.io/managed-by=Helm --overwrite
done

# 10. Deploy Kong Gateway
echo "🚀 Installing Kong with unified CP+DP config..."
helm upgrade --install kong kong/kong \
  --namespace kong \
  --create-namespace \
  --values ./configs/kong/kong-values.yaml

echo "✅ Kong deployed successfully at https://kong.helix"
