#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR

# ────────────────────────────────────────────────────────────────
# 🧪 Keycloak Sanity Check Script — Sherlock’s Magnifying Glass
# ────────────────────────────────────────────────────────────────

NAMESPACE="identity"
RELEASE="keycloak-helix"
REALM="helix"
POD=""

# ─── Utility Functions ───────────────────────────────────────────
log_info()  { echo -e "ℹ️  $*"; }
log_warn()  { echo -e "⚠️  $*"; }
log_success() { echo -e "✅ $*"; }

check_realm_exists() {
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    /opt/bitnami/keycloak/bin/kcadm.sh get realms \
    --server http://localhost:8080 \
    --realm master \
    --user admin --password admin 2>/dev/null | grep -q "\"realm\" : \"$REALM\""
}

# ─── Start Check ─────────────────────────────────────────────────
echo "🔍 Keycloak Integrity Check (Realm: $REALM, Namespace: $NAMESPACE)"
echo "🧠 Checking Keycloak pod..."

POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || {
  log_warn "No Keycloak pod found in namespace '$NAMESPACE'."
  exit 0
}

log_info "Using Keycloak pod: $POD"

echo ""
if ! kubectl exec -n "$NAMESPACE" "$POD" -- test -f "/opt/keycloak/configs/${REALM}-realm.json"; then
  log_warn "Realm JSON not found."
  echo "👉 You can either:"
  echo "   - Import it now via: ./bootstrap/deployment-phases/33_import-keycloak-realm.sh"
  echo "   - Or use the Keycloak UI: https://keycloak.helix/admin/"
fi

if ! check_realm_exists; then
  log_warn "Realm '$REALM' not found inside Keycloak."
  echo "👉 Run the importer or use the UI to create and configure the realm."
fi

# ─── 2. Check Theme Mounts ──────────────────────────────────────
echo ""
log_info "Inspecting mounted themes at /opt/keycloak/themes/$REALM..."
kubectl exec -n "$NAMESPACE" "$POD" -- ls -l "/opt/keycloak/themes/$REALM" || log_warn "Theme directory missing!"

log_info "Checking theme.properties..."
kubectl exec -n "$NAMESPACE" "$POD" -- cat "/opt/keycloak/themes/$REALM/theme.properties" || log_warn "theme.properties not found!"

log_info "Listing all theme files:"
kubectl exec -n "$NAMESPACE" "$POD" -- find "/opt/keycloak/themes/$REALM" -type f || true

# ─── 3. Check Realm JSON Mount ──────────────────────────────────
echo ""
log_info "Checking mounted realm JSON at /opt/keycloak/configs/${REALM}-realm.json..."
kubectl exec -n "$NAMESPACE" "$POD" -- test -f "/opt/keycloak/configs/${REALM}-realm.json" \
  && log_success "Realm JSON file mounted." \
  || log_warn "Realm JSON missing — you may import it later."

kubectl exec -n "$NAMESPACE" "$POD" -- ls -l "/opt/keycloak/configs/${REALM}-realm.json" || true
log_info "Content preview (first 10 lines):"
kubectl exec -n "$NAMESPACE" "$POD" -- head -n 10 "/opt/keycloak/configs/${REALM}-realm.json" || true

# ─── 4. Volume Mounts ───────────────────────────────────────────
echo ""
log_info "Verifying active mounts:"
kubectl exec -n "$NAMESPACE" "$POD" -- mount | grep "/opt/keycloak" || log_warn "No active mounts detected in /opt/keycloak"

# ─── 5. Helm Values ─────────────────────────────────────────────
echo ""
log_info "Checking Helm volume mounts (from Helm release values):"
helm get values "$RELEASE" -n "$NAMESPACE" --all | grep -A3 "extraVolumeMounts" || log_warn "No extra volume mounts found."

# ─── 6. Final Realm Check via `kcadmin` ─────────────────────────
echo ""
log_info "Verifying if realm '$REALM' exists in Keycloak:"
kubectl exec -n "$NAMESPACE" "$POD" -- \
  /opt/bitnami/keycloak/bin/kcadm.sh get realms \
  --server http://localhost:8080 \
  --realm master \
  --user admin --password admin | grep -q "\"realm\" : \"$REALM\"" \
  && log_success "Realm '$REALM' exists in Keycloak." \
  || log_warn "Realm '$REALM' not found in Keycloak."

echo ""
log_success "🎉 Keycloak integrity check complete."
