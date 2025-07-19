#!/bin/bash
# 🛠️ scripts/70-check-urls.sh – Helix platform sanity checker

set -e

CLUSTER=${1:-helix}
DOMAIN_SUFFIX=".$CLUSTER"

declare -A ENDPOINTS=(
  ["Keycloak"]="https://keycloak$DOMAIN_SUFFIX/admin/master/console/"
  ["Vault UI"]="https://vault$DOMAIN_SUFFIX/ui"
  ["Traefik Dashboard"]="https://traefik$DOMAIN_SUFFIX/dashboard"
  ["Keycloak Health"]="https://keycloak$DOMAIN_SUFFIX/health/ready"
)

echo "🔎 Performing curl health checks for cluster: $CLUSTER"
echo "----------------------------------------------------"

for name in "${!ENDPOINTS[@]}"; do
  URL="${ENDPOINTS[$name]}"
  echo -e "\n🔗 Checking ${name} → $URL"
  HTTP=$(curl -sk -o /dev/null -w "%{http_code}" "$URL" || echo "000")
  TIMEDIFF=$(curl -sw '%{time_total}\n' -o /dev/null -s "$URL" || echo "-")
  
  if [[ "$HTTP" =~ ^(200|302|401|403)$ ]]; then
    echo "✅ ${name}: HTTP $HTTP (responded in ${TIMEDIFF}s)"
  else
    echo "❌ ${name}: HTTP $HTTP"
    echo "     ➤ Tip: Try 'curl -vk $URL' and check DNS/Ingress rules"
  fi
done

echo -e "\n🔬 Cluster resource snapshot:"
kubectl get pods,svc,ing -n "$CLUSTER"

echo -e "\n🔐 Tip: If authentication fails on Keycloak console (401/403), check:"
echo "- Admin user: 'admin' / '$KC_PASS'"
echo "- Logs via: kubectl logs keycloak-${CLUSTER}-0 -n ${CLUSTER}"
echo ""

echo "🎉 Sanity check complete!"

echo "🔐 Here's a Keycloak token just for you to test via Postman for example 🔬"
curl -k -X POST https://keycloak.helix/realms/master/protocol/openid-connect/token \
  -d "client_id=admin-cli" \
  -d "grant_type=password" \
  -d "username=admin" \
  -d "password=admin"


