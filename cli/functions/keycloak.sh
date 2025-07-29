#!/usr/bin/env bash
set -euo pipefail
echo "✅ [keycloak.sh] Loaded!"

ENV_FILE="${ENV_FILE:-bootstrap/support/identity.env}"
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
else
  echo "❌ Cannot find identity.env at $ENV_FILE"; exit 1
fi

deploy_keycloak() {
  VAULT_NAMESPACE="-vault"
  # VAULT_POD_NAME="${VAULT_POD_NAME:-$(kubectl get pods -n "$VAULT_NAMESPACE" -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')}"
  
  # if [[ -z "$VAULT_POD_NAME" ]]; then
  #   echo "❌ No Vault pod found in namespace: $VAULT_NAMESPACE"; exit 1
  # fi
  # if [[ -z "$CLUSTER" ]]; then
  #   echo "❌ CLUSTER is not set"; exit 1
  # fi

  # echo "🔍 Found Vault pod: $VAULT_POD_NAME in namespace '$VAULT_NAMESPACE'"
  # echo "🛡️ Deploying Keycloak to namespace: '$NAMESPACE'"
  # READY_STATUS=$(kubectl get pod "$VAULT_POD_NAME" -n "$VAULT_NAMESPACE" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
  # if [[ "$READY_STATUS" != "true" ]]; then
  #   echo "❌ Vault pod '$VAULT_POD_NAME' is not Ready. Wait for it to be ready or check logs."
  #   exit 1
  # fi
  # echo "🔍 Found Vault pod: $VAULT_POD_NAME in namespace '$VAULT_NAMESPACE'"

  NAMESPACE="$(echo "${NAMESPACE:-}" | tr -d '\r')"
  KEYCLOAK_RELEASE="${KEYCLOAK_RELEASE:-keycloak-$CLUSTER}"
  DB_FQDN="${DB_FQDN:-postgresql-$CLUSTER.${NAMESPACE}.svc.cluster.local}"
  REALM_JSON="${REALM_JSON:-bootstrap/addon-configs/keycloak/realms/helix-realm.json}"
  PG_USER="${PG_USER:-keycloak}"
  PG_PASS="${PG_PASS:-pg_pass}"
  PG_DATABASE="${PG_DATABASE:-postgresql-$CLUSTER-db}"

  echo "🛡️ Deploying Keycloak to namespace: '$NAMESPACE'"
  echo "   • Release: $KEYCLOAK_RELEASE"
  echo "   • DB FQDN: $DB_FQDN"
  echo "   • PG User: $PG_USER"
  echo "   • PG DB: $PG_DATABASE"
  echo "   • Realm JSON: $REALM_JSON"

  [[ -f "$REALM_JSON" ]] || { echo "❌ Realm JSON not found: $REALM_JSON"; exit 1; }
  [[ -n "$NAMESPACE" ]] || { echo "❌ NAMESPACE is not set"; exit 1; }
  [[ -n "$CLUSTER" ]] || { echo "❌ CLUSTER is not set"; exit 1; }
  [[ -n "$POSTGRES_RELEASE" ]] || { echo "❌ POSTGRES_RELEASE is not set"; exit 1; }
  # [[ -n "$VAULT_POD_NAME" ]] || { echo "❌ VAULT_POD_NAME is not set"; exit 1; }

  kubectl get namespace "$NAMESPACE" &>/dev/null || {
    echo "➤ Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE"
  }

  if ! helm list -n "$NAMESPACE" | grep -q "$POSTGRES_RELEASE"; then
    echo "❌ Postgres release '$POSTGRES_RELEASE' missing; deploy Postgres first."; exit 1
  fi

  if helm list -n "$NAMESPACE" | grep -q "$KEYCLOAK_RELEASE"; then
    echo "⚠️ Helm release '$KEYCLOAK_RELEASE' exists; uninstalling..."
    helm uninstall "$KEYCLOAK_RELEASE" -n "$NAMESPACE" || true
    kubectl delete pvc -n "$NAMESPACE" -l app.kubernetes.io/instance="$KEYCLOAK_RELEASE" --ignore-not-found
  fi

  kubectl delete configmap helix-realm-config -n "$NAMESPACE" --ignore-not-found
  kubectl create configmap helix-realm-config --from-file=helix-realm.json="$REALM_JSON" \
    -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  kubectl label configmap helix-realm-config app.kubernetes.io/instance="$KEYCLOAK_RELEASE" \
    app.kubernetes.io/name=keycloak -n "$NAMESPACE" --overwrite

  cat > /tmp/keycloak_values.yaml <<EOF
auth:
  adminUser: ${ADMIN_USER:-admin}
  adminPassword: ${ADMIN_PASSWORD:-admin}
externalDatabase:
  host: "${DB_FQDN}"
  user: "${PG_USER}"
  password: "${PG_PASS}"
  database: "${PG_DATABASE}"
  port: 5432
ingress:
  enabled: true
  hostname: "$KEYCLOAK_RELEASE.${CLUSTER}"
  tls: true
proxy: edge
persistence:
  enabled: true
  size: 1Gi
EOF

  helm repo add bitnami https://charts.bitnami.com/bitnami --force-update &>/dev/null

  # spinner in background
  (
    while :; do
      for c in ⠇ ⠏ ⠋ ⠙ ⠹ ⠸ ⠼ ⠴; do printf "\r🚀 Deploying Keycloak... %s " "$c"; sleep 0.1; done
    done
  ) &
  SPID=$!

  helm upgrade --install "$KEYCLOAK_RELEASE" bitnami/keycloak \
    --namespace "$NAMESPACE" -f /tmp/keycloak_values.yaml \
    --set "extraEnv[0].name=KEYCLOAK_IMPORT" \
    --set "extraEnv[0].value=/opt/keycloak/data/import/helix-realm.json" \
    --set "extraVolumes[0].name=helix-realm" \
    --set "extraVolumes[0].configMap.name=helix-realm-config" \
    --set "extraVolumeMounts[0].name=helix-realm" \
    --set "extraVolumeMounts[0].mountPath=/opt/keycloak/data/import" \
    --timeout 900s

  kill "$SPID" &>/dev/null
  wait "$SPID" 2>/dev/null || true
  printf "\r✅ $KEYCLOAK_RELEASE deployed successfully!         \n"
  echo "🔍 Waiting for Keycloak pod to be ready..."
  kubectl rollout status statefulSet $KEYCLOAK_RELEASE" -n "$NAMESPACE" --timeout=300s
  echo "📦 Keycloak deployed successfully!"
} # This closes the deploy_keycloak function

store_keycloak_secrets() {
  echo "🔐 Storing Keycloak secrets in Vault..."
  kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD_NAME" -- /bin/sh -c "
    VAULT_ADDR='${VAULT_ADDR}' VAULT_TOKEN='${VAULT_ROOT_TOKEN}' \
    vault kv put secret/$KEYCLOAK_RELEASE \
      adminUser=$ADMIN_USER \
      adminPassword=$ADMIN_PASSWORD \
      databaseHost=$DB_FQDN \
      databaseUser=$PG_USER \
      databasePassword=$PG_PASS \
      databaseName=$PG_DATABASE
  "
  echo "✅ Secrets stored at secret/$KEYCLOAK_RELEASE"
}