#!/bin/bash
set -euo pipefail

# ========= Configurable Defaults =========
NAMESPACE="${NAMESPACE:-identity}"
RELEASE="${KEYCLOAK_RELEASE:-keycloak-helix}"
CLUSTER="${CLUSTER:-helix}"

# ========== Colors ==========
NC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'

echo -e "${CYAN}🧹 Starting cleanup for Keycloak in namespace: $NAMESPACE${NC}"

# ==== 1. Delete Helm release ====
if helm status "$RELEASE" -n "$NAMESPACE" &>/dev/null; then
  echo -e "${YELLOW}⚠️ Helm release '$RELEASE' found. Deleting...${NC}"
  helm uninstall "$RELEASE" -n "$NAMESPACE" || true
  echo -e "${GREEN}✅ Helm release '$RELEASE' deleted.${NC}"
else
  echo -e "${CYAN}ℹ️ No Helm release '$RELEASE' found in namespace $NAMESPACE${NC}"
fi

# ==== 2. Delete Keycloak PVCs ====
PVCs=$(kubectl get pvc -n "$NAMESPACE" -o name | grep keycloak || true)
if [[ -n "$PVCs" ]]; then
  echo -e "${YELLOW}⚠️ Deleting PVCs related to Keycloak...${NC}"
  echo "$PVCs" | xargs kubectl delete -n "$NAMESPACE"
  echo -e "${GREEN}✅ Keycloak PVCs removed.${NC}"
else
  echo -e "${CYAN}ℹ️ No Keycloak PVCs found in namespace $NAMESPACE${NC}"
fi

# ==== 3. Delete Keycloak secrets ====
SECRETS=$(kubectl get secrets -n "$NAMESPACE" -o name | grep keycloak || true)
if [[ -n "$SECRETS" ]]; then
  echo -e "${YELLOW}⚠️ Deleting Secrets related to Keycloak...${NC}"
  echo "$SECRETS" | xargs kubectl delete -n "$NAMESPACE"
  echo -e "${GREEN}✅ Keycloak secrets removed.${NC}"
else
  echo -e "${CYAN}ℹ️ No Keycloak-related secrets found.${NC}"
fi

# ==== 4. Delete ConfigMaps with realm/theme ====
CONFIGMAPS=$(kubectl get configmap -n "$NAMESPACE" -o name | grep "$CLUSTER"-realm-config || true)
if [[ -n "$CONFIGMAPS" ]]; then
  echo -e "${YELLOW}⚠️ Deleting realm-related ConfigMaps...${NC}"
  echo "$CONFIGMAPS" | xargs kubectl delete -n "$NAMESPACE"
  echo -e "${GREEN}✅ Realm ConfigMaps removed.${NC}"
else
  echo -e "${CYAN}ℹ️ No realm ConfigMaps found.${NC}"
fi

# ==== 5. Optionally delete ServiceAccounts ====
SA=$(kubectl get sa -n "$NAMESPACE" -o name | grep keycloak || true)
if [[ -n "$SA" ]]; then
  echo -e "${YELLOW}⚠️ Deleting ServiceAccounts related to Keycloak...${NC}"
  echo "$SA" | xargs kubectl delete -n "$NAMESPACE"
  echo -e "${GREEN}✅ ServiceAccounts removed.${NC}"
fi

echo -e "${GREEN}✅ Keycloak cleanup completed in namespace: $NAMESPACE${NC}"
echo -e "${CYAN}🌐 You can now redeploy Keycloak with a fresh configuration.${NC}"