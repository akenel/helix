#!/bin/bash
# Quick Helix Realm Creator - for the submarine empire!

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}🏰 Quick Helix Realm Setup for Submarine Empire${NC}"
echo

NAMESPACE="identity"
KC_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')

if [[ -z "$KC_POD" ]]; then
  echo -e "${RED}❌ No Keycloak pod found${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Found Keycloak pod: $KC_POD${NC}"

# Create basic Helix realm with submarine-empire theme
echo -e "${BLUE}🚢 Creating submarine empire realm...${NC}"

# Wait for Keycloak to be fully ready
kubectl exec -n "$NAMESPACE" "$KC_POD" -- bash -c "
until curl -s http://localhost:8080/health | grep -q UP; do
  echo 'Waiting for Keycloak...'
  sleep 5
done
echo 'Keycloak is ready!'
"

# Configure kcadm and create realm
kubectl exec -n "$NAMESPACE" "$KC_POD" -- bash -c "
# Configure kcadm
/opt/keycloak/bin/kcadm.sh config credentials \\
  --server http://localhost:8080 \\
  --realm master \\
  --user admin \\
  --password admin

# Create Helix realm
/opt/keycloak/bin/kcadm.sh create realms \\
  -s realm=helix \\
  -s displayName='Helix Submarine Empire' \\
  -s enabled=true \\
  -s registrationAllowed=true \\
  -s loginWithEmailAllowed=true \\
  -s duplicateEmailsAllowed=false

echo 'Helix realm created!'

# Create submarine-empire client
/opt/keycloak/bin/kcadm.sh create clients -r helix \\
  -s clientId=submarine-empire \\
  -s name='Submarine Empire 3D Printing' \\
  -s description='Where kids and parents design the submarines of their dreams' \\
  -s enabled=true \\
  -s clientAuthenticatorType=client-secret \\
  -s 'redirectUris=[\"https://keycloak.helix/*\"]' \\
  -s 'webOrigins=[\"https://keycloak.helix\"]'

echo 'Submarine Empire client created!'

# Create sample user: Jack (the submarine designer)
/opt/keycloak/bin/kcadm.sh create users -r helix \\
  -s username=jack \\
  -s firstName=Jack \\
  -s lastName='Submarine Designer' \\
  -s email=jack@submarine-empire.helix \\
  -s enabled=true

# Set password for Jack
USER_ID=\$(/opt/keycloak/bin/kcadm.sh get users -r helix -q username=jack --fields id --format csv --noquotes)
/opt/keycloak/bin/kcadm.sh set-password -r helix --userid \$USER_ID --new-password submarine123 --temporary

echo 'Jack the submarine designer created! (username: jack, password: submarine123)'

# List realms to confirm
echo 'Current realms:'
/opt/keycloak/bin/kcadm.sh get realms --fields realm,displayName
"

echo -e "${GREEN}✅ Helix Submarine Empire realm ready!${NC}"
echo -e "${YELLOW}🎮 Access:${NC}"
echo -e "   Admin Console: ${CYAN}https://keycloak.helix/admin${NC}"
echo -e "   Helix Realm: ${CYAN}https://keycloak.helix/realms/helix${NC}"
echo -e "   Test User: ${CYAN}jack / submarine123${NC}"
echo
echo -e "${BLUE}🚢 Ready to design submarines and run Popeye validation!${NC}"
