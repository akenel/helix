#!/bin/bash

# ────────────────────────────────────────────────
# 🔐 Helix Identity Provider - Keycloak Installer
# 🎩 bootstrap\deployment-phases\32_deploy-keycloak.sh
# 🛡️ Safe, Clean, Self-Healing Deployment Script
# ────────────────────────────────────────────────

set -euo pipefail
trap 'echo -e "\n❌ ${RED}Error on line $LINENO — aborting.${NC}"' ERR

# ───── Terminal Colors ─────
NC='\033[0m'; RED='\033[0;31m'; GREEN='\033[0;32m'
CYAN='\033[1;36m'; YELLOW='\033[1;33m'; BRIGHT_GREEN='\033[1;92m'

echo -e "\n${CYAN}🔐 Deploying Keycloak (Helix Identity Provider)...${NC}"

# ───── Constants ─────
NAMESPACE="identity"
REALM_FILE="./bootstrap/addon-configs/keycloak/realms/helix-realm-full.json"
REALM_CONFIGMAP="helix-realm-config"
THEME_CONFIGMAP="helix-theme"
DB_SECRET="keycloak-db-creds"
ADMIN_SECRET="keycloak-admin-creds"
POSTGRES_RELEASE="postgres"
KEYCLOAK_RELEASE="keycloak"
DB_NAME="keycloakdb"
DB_USER="pgadmin"
DB_PASS="supersecurepassword"
ADMIN_USER="admin"
ADMIN_PASS="admin"
DOMAIN="keycloak.helix"
VALUES_FILE="./bootstrap/addon-configs/keycloak/values/keycloak-values.yaml"

# ────────────────────────────────────────
# 🧼 Cleanup Previous Deployments
# ────────────────────────────────────────
echo -e "${YELLOW}🧼 Cleaning up previous deployments...${NC}"
helm uninstall $KEYCLOAK_RELEASE -n $NAMESPACE || true
helm uninstall $POSTGRES_RELEASE -n $NAMESPACE || true
kubectl delete pvc --all -n $NAMESPACE || true
kubectl delete configmap $REALM_CONFIGMAP $THEME_CONFIGMAP -n $NAMESPACE || true
kubectl delete secret $DB_SECRET $ADMIN_SECRET -n $NAMESPACE || true

# ────────────────────────────────────────
# 🏗️ Ensure Namespace Exists
# ────────────────────────────────────────
kubectl get namespace $NAMESPACE >/dev/null 2>&1 || kubectl create namespace $NAMESPACE

# ────────────────────────────────────────
# 🐘 Install PostgreSQL (Cetic Helm Chart)
# ────────────────────────────────────────
echo -e "${YELLOW}🐘 Installing PostgreSQL...${NC}"
helm repo add cetic https://cetic.github.io/helm-charts > /dev/null
helm repo update > /dev/null
helm upgrade --install $POSTGRES_RELEASE cetic/postgresql \
  -n $NAMESPACE \
  --version 0.2.5 \
  --set postgresqlDatabase=$DB_NAME \
  --set postgresqlUsername=$DB_USER \
  --set postgresqlPassword=$DB_PASS

# ────────────────────────────────────────
# 🔐 Secrets & ConfigMaps
# ────────────────────────────────────────
echo -e "${YELLOW}🔐 Creating Secrets & ConfigMaps...${NC}"

kubectl create secret generic $DB_SECRET \
  --from-literal=user="$DB_USER" \
  --from-literal=password="$DB_PASS" \
  -n $NAMESPACE

kubectl create secret generic $ADMIN_SECRET \
  --from-literal=username="$ADMIN_USER" \
  --from-literal=password="$ADMIN_PASS" \
  -n $NAMESPACE

kubectl create configmap $REALM_CONFIGMAP \
  --from-file=helix-realm.json="$REALM_FILE" \
  -n $NAMESPACE

kubectl create configmap $THEME_CONFIGMAP \
  --from-literal=theme.properties='parent=keycloak' \
  -n $NAMESPACE

# ────────────────────────────────────────
# 📦 Phase 1: Realm Import
# ────────────────────────────────────────
echo -e "${YELLOW}📦 Importing Realm Configuration...${NC}"

cat > "$VALUES_FILE" << EOF
postgresql:
  enabled: false

image:
  repository: quay.io/keycloak/keycloak
  tag: "24.0.3"

command:
  - "/opt/keycloak/bin/kc.sh"
args:
  - "import"
  - "--file"
  - "/opt/keycloak/data/import/helix-realm.json"

extraEnv: |
  - name: DB_VENDOR
    value: postgres
  - name: DB_ADDR
    value: ${POSTGRES_RELEASE}.${NAMESPACE}.svc.cluster.local
  - name: DB_PORT
    value: "5432"
  - name: DB_DATABASE
    value: ${DB_NAME}
  - name: DB_USER_FILE
    value: /secrets/db-creds/user
  - name: DB_PASSWORD_FILE
    value: /secrets/db-creds/password

extraVolumeMounts: |
  - name: db-creds
    mountPath: /secrets/db-creds
    readOnly: true
  - name: realm-config
    mountPath: /opt/keycloak/data/import
    readOnly: true

extraVolumes: |
  - name: db-creds
    secret:
      secretName: $DB_SECRET
  - name: realm-config
    configMap:
      name: $REALM_CONFIGMAP
EOF

helm repo add codecentric https://codecentric.github.io/helm-charts > /dev/null
helm repo update > /dev/null
helm upgrade --install $KEYCLOAK_RELEASE codecentric/keycloak \
  -n $NAMESPACE \
  -f "$VALUES_FILE"

echo -e "${GREEN}✅ Realm imported. Proceeding to final deployment...${NC}"
sleep 10

# ────────────────────────────────────────
# 🚀 Phase 2: Start Keycloak Server
# ────────────────────────────────────────
echo -e "${YELLOW}🚀 Deploying Keycloak Server...${NC}"

cat > "$VALUES_FILE" << EOF
replicaCount: 1

image:
  repository: quay.io/keycloak/keycloak
  tag: "24.0.3"
  pullPolicy: IfNotPresent

command:
  - "/opt/keycloak/bin/kc.sh"
args:
  - "start-dev"
  - "--import-realm"

postgresql:
  enabled: false

extraEnv: |
  - name: DB_VENDOR
    value: postgres
  - name: DB_ADDR
    value: ${POSTGRES_RELEASE}.${NAMESPACE}.svc.cluster.local
  - name: DB_PORT
    value: "5432"
  - name: DB_DATABASE
    value: ${DB_NAME}
  - name: DB_USER_FILE
    value: /secrets/db-creds/user
  - name: DB_PASSWORD_FILE
    value: /secrets/db-creds/password
  - name: KEYCLOAK_ADMIN
    value: ${ADMIN_USER}
  - name: KEYCLOAK_ADMIN_PASSWORD
    value: ${ADMIN_PASS}
  - name: KC_PROXY
    value: edge
  - name: KC_HOSTNAME
    value: ${DOMAIN}  
  - name: KC_HOSTNAME_STRICT
    value: "false"

extraVolumeMounts: |
  - name: db-creds
    mountPath: /secrets/db-creds
    readOnly: true

extraVolumes: |
  - name: db-creds
    secret:
      secretName: $DB_SECRET

ingress:
  enabled: true
  ingressClassName: "traefik"
  annotations:
    cert-manager.io/cluster-issuer: "mkcert-ca-issuer"
    traefik.ingress.kubernetes.io/router.entrypoints: "websecure"
    traefik.ingress.kubernetes.io/router.tls: "true"
  rules:
    - host: ${DOMAIN}
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - ${DOMAIN}
      secretName: keycloak-helix-tls

resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1"

startupProbe: |
  httpGet:
    path: /
    port: 8080
  initialDelaySeconds: 600
  timeoutSeconds: 5
  periodSeconds: 10
  failureThreshold: 12

readinessProbe: |
  httpGet:
    path: /
    port: 8080
  initialDelaySeconds: 600
  timeoutSeconds: 5
  periodSeconds: 10
  failureThreshold: 5

livenessProbe: |
  httpGet:
    path: /
    port: 8080
  initialDelaySeconds: 600
  timeoutSeconds: 5
  periodSeconds: 10
  failureThreshold: 5
EOF

helm upgrade --install $KEYCLOAK_RELEASE codecentric/keycloak \
  -n $NAMESPACE \
  -f "$VALUES_FILE"
KEYCLOAK_POD=$(kubectl get pods -n identity -l app.kubernetes.io/name=keycloak -o jsonpath="{.items[0].metadata.name}")
kubectl wait --for=condition=Ready pod/"$KEYCLOAK_POD" -n identity --timeout=1800s
echo -e "${GREEN}✅ Keycloak server deployed successfully!${NC}"
sleep 30
# ────────────────────────────────────────
# ✅ Final Summary
# ────────────────────────────────────────
echo -e "\n${GREEN}✅ Deployment complete!${NC}"
echo -e "🔑 Realm URL: ${BRIGHT_GREEN}https://${DOMAIN}${NC}"
echo -e "🧑 Admin Login: ${BRIGHT_GREEN}${ADMIN_USER} / ${ADMIN_PASS}${NC}"
echo -e "🗄️  PostgreSQL: ${BRIGHT_GREEN}${DB_NAME} @ ${POSTGRES_RELEASE}.${NAMESPACE}.svc.cluster.local${NC}"
echo "🧾 Deployment Summary:"
printf "%-25s %s\n" "Cluster Name:" "helix"
printf "%-25s %s\n" "Keycloak URL:" "https://keycloak.helix"
printf "%-25s %s\n" "Vault UI:"     "https://vault.helix"
printf "%-25s %s\n" "Traefik UI:"   "https://traefik.helix"
printf "%-25s %s\n" "PostgreSQL:"   "postgres.identity.svc.cluster.local"
echo -e "${CYAN}🔗 Access Keycloak at: https://${DOMAIN}${NC}"