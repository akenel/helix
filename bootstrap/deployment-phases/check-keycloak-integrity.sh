#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR

# 🧪 Keycloak Sanity Check Script — Sherlock’s Magnifying Glass 🕵️‍♂️
# Verifies Keycloak pod, realm config, and theme mounting.

NAMESPACE="identity"
RELEASE="keycloak-helix"
REALM="helix"
POD=""

echo "🔍 Keycloak Integrity Check (Realm: $REALM, Namespace: $NAMESPACE)"

#──────────────────────────────────────────────────────
# 🔎 1. Get Pod
#──────────────────────────────────────────────────────
echo "🧠 Checking Keycloak pod..."
POD=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z "$POD" ]]; then
  echo "❌ No Keycloak pod found in namespace '$NAMESPACE'"
  exit 1
fi
echo "✅ Pod: $POD"

#──────────────────────────────────────────────────────
# 🔖 2. Check Theme Mounts
#──────────────────────────────────────────────────────
echo "🎨 Inspecting mounted themes at /opt/keycloak/themes/$REALM..."
kubectl exec -n "$NAMESPACE" "$POD" -- ls -l "/opt/keycloak/themes/$REALM" || echo "⚠️ Theme directory missing!"

echo "📄 Checking theme.properties..."
kubectl exec -n "$NAMESPACE" "$POD" -- cat "/opt/keycloak/themes/$REALM/theme.properties" || echo "⚠️ theme.properties not found!"

echo "🧾 Listing all theme files:"
kubectl exec -n "$NAMESPACE" "$POD" -- find "/opt/keycloak/themes/$REALM" -type f || true

#──────────────────────────────────────────────────────
# 📦 3. Check Realm JSON
#──────────────────────────────────────────────────────
echo "🧾 Checking mounted realm JSON at /opt/keycloak/configs/${REALM}-realm.json..."
kubectl exec -n "$NAMESPACE" "$POD" -- test -f "/opt/keycloak/configs/${REALM}-realm.json" && echo "✅ Realm JSON file mounted." || echo "❌ Missing realm JSON!"

echo "📄 Content preview (first 10 lines):"
kubectl exec -n "$NAMESPACE" "$POD" -- head -n 10 "/opt/keycloak/configs/${REALM}-realm.json" || true

#──────────────────────────────────────────────────────
# 🔩 4. Active Volume Mounts
#──────────────────────────────────────────────────────
echo "🔗 Verifying active mounts:"
kubectl exec -n "$NAMESPACE" "$POD" -- mount | grep "/opt/keycloak"

#──────────────────────────────────────────────────────
# 📜 5. Helm Values
#──────────────────────────────────────────────────────
echo "📦 Checking Helm volume mounts (from Helm release values):"
helm get values "$RELEASE" -n "$NAMESPACE" --all | grep -A3 "extraVolumeMounts"

#──────────────────────────────────────────────────────
# 🕵️ 6. Realm Presence via kcadmin
#──────────────────────────────────────────────────────
echo "🔐 Verifying if realm '$REALM' exists in Keycloak:"
kubectl exec -n "$NAMESPACE" "$POD" -- \
  /opt/bitnami/keycloak/bin/kcadm.sh get realms \
  --server http://localhost:8080 \
  --realm master \
  --user admin --password admin | grep -q "\"realm\" : \"$REALM\"" && \
  echo "✅ Realm '$REALM' exists in Keycloak." || \
  echo "❌ Realm '$REALM' not found in Keycloak."

echo "✅ All checks completed."
