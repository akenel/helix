
!/bin/bash

🔑 Imports the helix-dev.json realm into Keycloak via kcadm CLI

set -e

echo "🌍 Importing Helix Realm into Keycloak..."

Assumes running inside Keycloak pod with admin creds
kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password admin

kcadm.sh create realms -f /scripts/keycloak/helix-dev.json

echo "✅ Realm 'helix' imported successfully!"