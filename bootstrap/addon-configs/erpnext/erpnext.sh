#!/usr/bin/env bash
set -euo pipefail

NC='\033[0m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'

LOG_FILE="erpnext-install.log"
DEBUG=false
ATOMIC=false

for arg in "$@"; do
  case $arg in
    --debug) DEBUG=true ;;
    --atomic) ATOMIC=true ;;
  esac
done

log() { echo -e "$1" | tee -a "$LOG_FILE"; }
debug() { $DEBUG && log "${YELLOW}🐞 [DEBUG] $*${NC}"; }

log "${CYAN}🚀 Starting ERPNext install...${NC}"
debug "Script args: $*"

if ! kubectl get ns erpnext &>/dev/null; then
  log "${YELLOW}📦 Creating namespace: erpnext${NC}"
  kubectl create namespace erpnext | tee -a "$LOG_FILE"
else
  log "${GREEN}✅ Namespace 'erpnext' already exists.${NC}"
fi

if ! helm repo list | grep -q '^frappe'; then
  log "${YELLOW}➕ Adding Frappe Helm repo...${NC}"
  helm repo add frappe https://helm.erpnext.com | tee -a "$LOG_FILE"
else
  log "${GREEN}✅ Frappe Helm repo already added.${NC}"
fi

log "${CYAN}🔄 Updating Helm repos...${NC}"
helm repo update | tee -a "$LOG_FILE"

HELM_CMD=(helm upgrade --install frappe-bench --namespace erpnext frappe/erpnext --values erpnext-values.yaml)
$ATOMIC && HELM_CMD+=(--atomic)

log "${CYAN}🚢 Deploying ERPNext with Helm...${NC}"
if $DEBUG; then
  log "${YELLOW}🐞 Running: ${HELM_CMD[*]} --debug${NC}"
  "${HELM_CMD[@]}" --debug | tee -a "$LOG_FILE"
else
  "${HELM_CMD[@]}" | tee -a "$LOG_FILE"
fi

if [[ $? -eq 0 ]]; then
  log "${GREEN}🎉 ERPNext deployed successfully!${NC}"
else
  log "${RED}❌ ERPNext deployment failed. Check $LOG_FILE for details.${NC}"
  exit 1
fi

log "${CYAN}📄 See $LOG_FILE for full output.${NC}"