#!/bin/bash
# 🧠 Post-Keycloak Bootstrap Script — 33_post_keycloak_initialize.sh

set -euo pipefail

# ─── Find Keycloak Pod ────────────────────────────────
KEYCLOAK_POD=$(kubectl get pod -n identity -l app.kubernetes.io/name=keycloak -o jsonpath="{.items[0].metadata.name}")
echo "🔍 Found Keycloak pod: $KEYCLOAK_POD"

# ─── File Locations ───────────────────────────────────
REALM_FILE="./bootstrap/addon-configs/keycloak/realms/helix3d-realm.json"
REALM_JSON="/tmp/helix3d-realm.json"   # <── CHANGED
echo "📂 Using realm JSON path inside pod: $REALM_JSON"

# ─── Step 2: Inject Realm JSON into Pod ───────────────
echo "📤 Copying realm file into Keycloak container (without tar)..."
cat "$REALM_FILE" | kubectl exec -i -n identity "$KEYCLOAK_POD" -- tee "$REALM_JSON" > /dev/null
kubectl exec -n identity "$KEYCLOAK_POD" -- ls -la /opt/keycloak/data
# ─── Step 3: Create Realm from File ───────────────────
echo "📜 Creating realm 'helix3d' from JSON file..."
# ─── Step 1: Log in to Keycloak Admin CLI ─────────────
echo "🔑 Executing Post-Bootstrap Keycloak Initialization..."
kubectl exec -n identity "$KEYCLOAK_POD" -- /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password admin

# ─── Step 2: Inject Realm JSON into Pod ───────────────
echo "📤 Copying realm file into Keycloak container (without tar)..."
cat "$REALM_FILE" | kubectl exec -i -n identity "$KEYCLOAK_POD" -- tee "$REALM_JSON" > /dev/null

# ─── Step 3: Create Realm from File ───────────────────
kubectl exec -n identity "$KEYCLOAK_POD" -- /opt/keycloak/bin/kcadm.sh create realms -f "$REALM_JSON"

echo "✅ Realm 'helix3d' created successfully!"

