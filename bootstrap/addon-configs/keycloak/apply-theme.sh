#!/bin/bash
# Helper script to apply Helix theme to Keycloak
# Usage: ./apply-theme.sh <cluster> <namespace>

set -euo pipefail

CLUSTER="${1:-helix}"
NAMESPACE="${2:-identity}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_DIR="$SCRIPT_DIR/themes/$CLUSTER"

# Colors
NC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'

echo -e "${CYAN}🎨 Applying theme for cluster: $CLUSTER${NC}"

# Check if theme directory exists
if [[ ! -d "$THEME_DIR" ]]; then
  echo -e "${RED}❌ Theme directory not found: $THEME_DIR${NC}"
  echo -e "💡 Create theme files in themes/$CLUSTER directory"
  exit 1
fi

# Get Keycloak pod
KC_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$KC_POD" ]]; then
  echo -e "${RED}❌ No Keycloak pod found in namespace: $NAMESPACE${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Found Keycloak pod: $KC_POD${NC}"

# Create theme directory in pod
echo -e "${CYAN}📁 Creating theme directory in Keycloak pod...${NC}"
kubectl exec -n "$NAMESPACE" "$KC_POD" -- mkdir -p "/opt/keycloak/themes/$CLUSTER"

# Copy theme files
echo -e "${CYAN}📁 Copying theme files...${NC}"
kubectl cp "$THEME_DIR/." "$NAMESPACE/$KC_POD:/opt/keycloak/themes/$CLUSTER/"

# Restart Keycloak to pick up theme changes
echo -e "${CYAN}🔄 Restarting Keycloak to apply theme...${NC}"
kubectl rollout restart deployment "keycloak-$CLUSTER" -n "$NAMESPACE"
kubectl rollout status deployment "keycloak-$CLUSTER" -n "$NAMESPACE" --timeout=300s

echo -e "${GREEN}✅ Theme applied successfully!${NC}"
echo -e "🎨 Theme '$CLUSTER' is now available in Keycloak admin console"
