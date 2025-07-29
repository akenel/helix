#!/bin/bash
# Helper script to import Helix realm into Keycloak
# Usage: ./import-realm.sh <cluster> <namespace>

set -euo pipefail

CLUSTER="${1:-helix}"
NAMESPACE="${2:-identity}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REALM_JSON="$SCRIPT_DIR/realms/helix-realm.json"

# Colors
NC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'

echo -e "${CYAN}🏰 Importing realm for cluster: $CLUSTER${NC}"

# Check if realm JSON exists
if [[ ! -f "$REALM_JSON" ]]; then
  echo -e "${RED}❌ Realm JSON not found: $REALM_JSON${NC}"
  echo -e "💡 Create a realm export or place helix-realm.json in the realms directory"
  exit 1
fi

# Get Keycloak pod
KC_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$KC_POD" ]]; then
  echo -e "${RED}❌ No Keycloak pod found in namespace: $NAMESPACE${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Found Keycloak pod: $KC_POD${NC}"

# Wait for Keycloak to be fully ready
echo -e "${CYAN}⌛ Waiting for Keycloak to be fully ready...${NC}"
sleep 30

# Copy realm JSON to pod
echo -e "${CYAN}📁 Copying realm JSON to Keycloak pod...${NC}"
kubectl cp "$REALM_JSON" "$NAMESPACE/$KC_POD:/tmp/helix-realm.json"

# Import realm using kcadm (Keycloak Admin CLI)
echo -e "${CYAN}🚀 Importing realm via kcadm...${NC}"
kubectl exec -n "$NAMESPACE" "$KC_POD" -- bash -c "
  /opt/keycloak/bin/kcadm.sh config credentials \
    --server http://localhost:8080 \
    --realm master \
    --user admin \
    --password admin
  
  /opt/keycloak/bin/kcadm.sh create realms \
    -f /tmp/helix-realm.json || echo 'Realm may already exist'
"

echo -e "${GREEN}✅ Realm import completed!${NC}"
echo -e "🌐 You can now access: https://keycloak.$CLUSTER/admin"
