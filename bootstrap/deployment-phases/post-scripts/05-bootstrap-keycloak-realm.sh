#!/bin/bash
set -euo pipefail

echo "Importing Helix Realm into Keycloak..."

KC_POD=$(kubectl get pods -n identity -l app.kubernetes.io/name=keycloak --no-headers | awk '{print $1}')

if [ -z "$KC_POD" ]; then
    echo "Error: Keycloak pod not found in 'identity' namespace. Ensure Keycloak is deployed and running."
    exit 1
fi

echo "Found Keycloak pod: $KC_POD"

# Check if the realm already exists to make the script idempotent (optional but good)
# You might need to adjust the Keycloak admin credentials or get them from a secret
ADMIN_USER="admin"
ADMIN_PASS="keycloakadmin" # For dev, ideally from secret for prod

# Authenticate and check if realm exists
REALM_EXISTS=$(kubectl exec -n identity "$KC_POD" -- bash -c "
  kcadm.sh config credentials --server http://localhost:8080 --realm master --user $ADMIN_USER --password $ADMIN_PASS > /dev/null 2>&1
  kcadm.sh get realms/helix --fields realm -q > /dev/null 2>&1
  echo \$?
")

if [ "$REALM_EXISTS" -eq 0 ]; then
    echo "Helix realm already exists. Skipping import."
else
    echo "Importing helix-realm.json..."
    kubectl exec -n identity "$KC_POD" -- bash -c "
      kcadm.sh config credentials --server http://localhost:8080 \
        --realm master --user $ADMIN_USER --password $ADMIN_PASS && \
      kcadm.sh create realms -f /opt/keycloak/configs/helix-realm.json
    "
    echo "Helix realm imported."
fi

echo "Keycloak realm import complete."