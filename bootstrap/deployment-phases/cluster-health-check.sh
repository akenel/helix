#!/bin/bash

set -euo pipefail

trap '[[ -n "${KUBECONFIG_TEMP:-}" ]] && rm -f "$KUBECONFIG_TEMP"' EXIT INT TERM

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🎩 69 - Helix Cluster Royal Health Check + Popeye Integration
# 🔍 Platform Integrity, Identity & TLS Inspection + Dynamic Status
# 👑 By Angel + Popeye Power
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Colors for beautiful output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[1;35m'
NC='\033[0m'

# Dynamic Status Tracking
declare -A SERVICE_STATUS
declare -A SERVICE_DETAILS

# Initialize all services as "checking"
SERVICE_STATUS=(
    ["cluster"]="🔄"
    ["nodes"]="🔄"
    ["cert-manager"]="🔄"
    ["keycloak"]="🔄"
    ["vault"]="🔄"
    ["ingress"]="🔄"
    ["popeye"]="🔄"
)

SERVICE_DETAILS=(
    ["cluster"]="K3s Cluster API"
    ["nodes"]="Worker Nodes"
    ["cert-manager"]="Certificate Management"
    ["keycloak"]="Identity & Authentication"
    ["vault"]="Secrets Management"
    ["ingress"]="External Access Points"
    ["popeye"]="Enterprise Validation"
)

update_service_status() {
    local service=$1
    local status=$2
    local detail=${3:-""}
    SERVICE_STATUS[$service]=$status
    if [[ -n $detail ]]; then
        SERVICE_DETAILS[$service]="$detail"
    fi
}

show_dynamic_summary() {
    echo -e "\n${CYAN}🎯 HELIX DEPLOYMENT SUMMARY - REAL-TIME STATUS${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    for service in cluster nodes cert-manager keycloak vault ingress popeye; do
        local status="${SERVICE_STATUS[$service]}"
        local detail="${SERVICE_DETAILS[$service]}"
        
        if [[ $status == "✅" ]]; then
            echo -e "${GREEN}$status $service${NC} - $detail"
        elif [[ $status == "❌" ]]; then
            echo -e "${RED}$status $service${NC} - $detail"
        elif [[ $status == "⚠️" ]]; then
            echo -e "${YELLOW}$status $service${NC} - $detail"
        else
            echo -e "${BLUE}$status $service${NC} - $detail"
        fi
    done
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

run_popeye_validation() {
    echo -e "\n${MAGENTA}🥫 Running Popeye Enterprise Validation...${NC}"
    
    if command -v popeye &> /dev/null; then
        update_service_status "popeye" "🔄" "Running validation scan..."
        show_dynamic_summary
        
        mkdir -p "$LOG_DIR/popeye-reports"
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        
        if popeye > "$LOG_DIR/popeye-reports/health-check-validation-${timestamp}.txt" 2>&1; then
            update_service_status "popeye" "✅" "Enterprise validation passed"
            
            # Extract key metrics from Popeye output
            local popeye_summary=""
            if [[ -f "$LOG_DIR/popeye-reports/health-check-validation-${timestamp}.txt" ]]; then
                local errors=$(grep -c "ERROR" "$LOG_DIR/popeye-reports/health-check-validation-${timestamp}.txt" 2>/dev/null || echo "0")
                local warnings=$(grep -c "WARN" "$LOG_DIR/popeye-reports/health-check-validation-${timestamp}.txt" 2>/dev/null || echo "0")
                popeye_summary="Errors: $errors, Warnings: $warnings"
                update_service_status "popeye" "✅" "Enterprise validation: $popeye_summary"
            fi
            
            echo -e "${GREEN}✅ Popeye validation complete: $popeye_summary${NC}"
            echo -e "${CYAN}📁 Report saved: $LOG_DIR/popeye-reports/health-check-validation-${timestamp}.txt${NC}"
        else
            update_service_status "popeye" "⚠️" "Validation completed with issues"
            echo -e "${YELLOW}⚠️ Popeye validation completed with issues${NC}"
        fi
    else
        update_service_status "popeye" "❌" "Popeye not installed"
        echo -e "${RED}❌ Popeye not found. Install with: snap install popeye${NC}"
    fi
}

echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
echo "🔐 Helix Platform Cluster Health Audit + Popeye"
echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"

# Show initial status
show_dynamic_summary

# Kubeconfig override
export KUBECONFIG="${KUBECONFIG:-$HOME/.helix/kubeconfig.yaml}"

# 🧪 Check cluster access
update_service_status "cluster" "🔄" "Connecting to Kubernetes API..."
show_dynamic_summary

kubectl config use-context k3d-helix >/dev/null 2>&1 || {
  echo -e "\e[31m❌ Unable to connect to Kubernetes API. Check kubeconfig or cluster status.\e[0m"
  update_service_status "cluster" "❌" "API connection failed"
  show_dynamic_summary
  exit 1
}

update_service_status "cluster" "✅" "K3s API connected successfully"

# 📦 Dependency checks
for bin in curl jq docker ip date tee vault; do
  command -v "$bin" >/dev/null || {
    echo "❗ Required binary '$bin' missing. Aborting."
    exit 1
  }
done

# 📜 Summary Logs
LOG_DIR="logs/$(date +%Y%m%d)"
mkdir -p "$LOG_DIR"
SUMMARY_LOG="$LOG_DIR/helix_deployment_summary.log"
touch "$SUMMARY_LOG"

log_summary() {
  local type=$1 msg=$2 ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[${ts}] [${type}] $msg" | tee -a "$SUMMARY_LOG"
}

# 🗺️ Geo & Environment Check
HOST_IP=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
DOCKER_VER=$(docker version --format '{{.Client.Version}}/{{.Server.Version}}' 2>/dev/null || echo "N/A")
LINUX_INFO=$(uname -srm)

CITY="Unknown"; REGION="Unknown"; COUNTRY="Unknown"; TEMP="N/A"; WIND="N/A"
LOCATION_JSON=$(curl -s https://ipapi.co/json/)
if [[ -n "$LOCATION_JSON" ]]; then
  CITY=$(echo "$LOCATION_JSON" | jq -r '.city')
  REGION=$(echo "$LOCATION_JSON" | jq -r '.region')
  COUNTRY=$(echo "$LOCATION_JSON" | jq -r '.country_name')
  LAT=$(echo "$LOCATION_JSON" | jq -r '.latitude')
  LON=$(echo "$LOCATION_JSON" | jq -r '.longitude')
  if [[ "$LAT" != "0" && "$LON" != "0" ]]; then
    WEATHER_JSON=$(curl -s "https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}&current_weather=true")
    TEMP=$(echo "$WEATHER_JSON" | jq -r '.current_weather.temperature')
    WIND=$(echo "$WEATHER_JSON" | jq -r '.current_weather.windspeed')
  fi
fi

# 📊 Environment Summary
log_summary INFO "Geo: ${CITY}, ${REGION}, ${COUNTRY}"
log_summary INFO "Weather: ${TEMP}°C, Wind ${WIND} km/h"
log_summary INFO "Host IP: $HOST_IP"
log_summary INFO "Docker: $DOCKER_VER"
log_summary INFO "OS: $LINUX_INFO"

echo -e "\n🩺 Cluster Environment at $(date)"
echo "📍 Location: $CITY, $REGION, $COUNTRY"
echo "🌤️ Weather: ${TEMP}°C, Wind ${WIND} km/h"
echo "🐧 OS: $LINUX_INFO • 🐳 Docker: $DOCKER_VER"
echo "---------------------------------------------"

# 🌐 Cluster Status
echo "🔍 Connected Clusters:"
k3d cluster list | awk 'NR>1 {print "🟢 " $1}'
echo ""

# 📡 Select Cluster
read -p "🤖 Cluster name to inspect [default: helix]: " CLUSTER_NAME
CLUSTER_NAME=${CLUSTER_NAME:-helix}
if ! k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo -e "\e[31m❌ Cluster '$CLUSTER_NAME' not found.\e[0m"
  exit 1
fi

KUBECONFIG_TEMP=$(mktemp)
k3d kubeconfig get "$CLUSTER_NAME" > "$KUBECONFIG_TEMP"
sed -i 's|host.docker.internal|127.0.0.1|g' "$KUBECONFIG_TEMP"
export KUBECONFIG="$KUBECONFIG_TEMP"

# 🔄 Kubeconfig Patching
kubectl config set-cluster "k3d-${CLUSTER_NAME}" --server="https://127.0.0.1:6550" &>/dev/null
kubectl config use-context "k3d-${CLUSTER_NAME}" &>/dev/null

echo "✅ Using context: k3d-${CLUSTER_NAME} (API patched to 127.0.0.1)"
kubectl cluster-info || { echo "❌ Cluster unreachable"; exit 1; }

# 🧩 Node & Pod Health
echo -e "\n🧱 Nodes"
update_service_status "nodes" "🔄" "Checking node health..."
show_dynamic_summary

kubectl get nodes -o wide
node_count=$(kubectl get nodes --no-headers | wc -l)
ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready" || echo "0")

if [[ $ready_nodes -eq $node_count && $node_count -gt 0 ]]; then
    update_service_status "nodes" "✅" "$ready_nodes/$node_count nodes ready"
else
    update_service_status "nodes" "⚠️" "$ready_nodes/$node_count nodes ready"
fi

echo -e "\n📦 Pods by Namespace"
kubectl get pods --all-namespaces

echo -e "\n🚨 Non-Ready Pods"
non_ready_pods=$(kubectl get pods --all-namespaces --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
if [[ $non_ready_pods -eq 0 ]]; then
    echo "✅ All pods running"
else
    echo "⚠️ $non_ready_pods pods not running"
    kubectl get pods --all-namespaces --field-selector=status.phase!=Running --no-headers
fi

# 🧪 Cert-Manager Status
echo -e "\n🔐 Cert-Manager"
update_service_status "cert-manager" "🔄" "Checking certificate management..."
show_dynamic_summary

if kubectl get pods -n cert-manager &>/dev/null; then
    cert_manager_pods=$(kubectl get pods -n cert-manager --no-headers | grep -c "Running" || echo "0")
    total_cert_pods=$(kubectl get pods -n cert-manager --no-headers | wc -l)
    
    if [[ $cert_manager_pods -eq $total_cert_pods && $total_cert_pods -gt 0 ]]; then
        update_service_status "cert-manager" "✅" "$cert_manager_pods/$total_cert_pods pods running"
    else
        update_service_status "cert-manager" "⚠️" "$cert_manager_pods/$total_cert_pods pods running"
    fi
    kubectl get pods -n cert-manager
else
    update_service_status "cert-manager" "❌" "Namespace not found"
    echo "❌ Cert-manager not found"
fi

# 👁️ Identity System Check: Keycloak
echo -e "\n👤 Keycloak Identity Status"
update_service_status "keycloak" "🔄" "Checking identity system..."
show_dynamic_summary

if kubectl get pods -n identity | grep -q keycloak; then
  KC_POD=$(kubectl get pods -n identity -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')
  echo "🟢 Keycloak Pod: $KC_POD"
  
  # Check if pod is running
  kc_status=$(kubectl get pod -n identity "$KC_POD" -o jsonpath='{.status.phase}')
  if [[ $kc_status == "Running" ]]; then
      update_service_status "keycloak" "✅" "Pod running, checking realm..."
      show_dynamic_summary
      
      echo "🔐 Checking realm 'helix'..."
      if kubectl exec -n identity "$KC_POD" -- kcadm.sh config credentials \
        --server http://localhost:8080 --realm master \
        --user admin --password admin &>/dev/null; then
        
        echo "✅ KCADM authenticated"
        if kubectl exec -n identity "$KC_POD" -- kcadm.sh get realms/helix &>/dev/null; then
            update_service_status "keycloak" "✅" "Realm 'helix' configured"
        else
            update_service_status "keycloak" "⚠️" "Realm 'helix' missing"
            echo "❌ Realm not found"
        fi
      else
        update_service_status "keycloak" "⚠️" "Authentication failed"
      fi
  else
      update_service_status "keycloak" "❌" "Pod not running ($kc_status)"
  fi
else
  update_service_status "keycloak" "❌" "Pod missing in identity namespace"
  echo "❌ Keycloak pod missing in 'identity' namespace"
fi

# 🗝️ Vault Status
echo -e "\n🔐 Vault Status"
update_service_status "vault" "🔄" "Checking secrets management..."
show_dynamic_summary

if command -v vault &>/dev/null && [[ -n "${VAULT_ADDR:-}" ]]; then
  if vault status &>/dev/null; then
    vault_sealed=$(vault status | grep "Sealed" | awk '{print $2}')
    if [[ $vault_sealed == "false" ]]; then
        update_service_status "vault" "✅" "Unsealed and accessible"
    else
        update_service_status "vault" "⚠️" "Sealed"
    fi
    vault status
  else
    update_service_status "vault" "❌" "CLI connection failed"
    echo "⚠️ Vault CLI failed"
  fi
else
  update_service_status "vault" "⚠️" "Not configured or CLI missing"
  echo "⚠️ Vault not configured or CLI missing"
fi

# 📍 Services Summary
echo -e "\n🧭 Ingress Points"
update_service_status "ingress" "�" "Checking external access points..."
show_dynamic_summary

ingress_services=(
    "portainer.helix"
    "keycloak.helix"
    "vault.helix"
    "adminer.helix"
    "traefik.helix"
)

working_ingress=0
total_ingress=${#ingress_services[@]}

for service in "${ingress_services[@]}"; do
    if curl -k -s --connect-timeout 5 "https://$service" >/dev/null 2>&1; then
        echo "� https://$service - Online"
        ((working_ingress++))
    else
        echo "� https://$service - Offline/Unreachable"
    fi
done

if [[ $working_ingress -eq $total_ingress ]]; then
    update_service_status "ingress" "✅" "All $total_ingress services accessible"
elif [[ $working_ingress -gt 0 ]]; then
    update_service_status "ingress" "⚠️" "$working_ingress/$total_ingress services accessible"
else
    update_service_status "ingress" "❌" "No services accessible"
fi

# Run Popeye validation
run_popeye_validation

# 📊 Final Scorecard with Enhanced Metrics
echo -e "\n📋 Cluster Scorecard"
namespaces=$(kubectl get ns --no-headers | wc -l)
nodes=$(kubectl get nodes --no-headers | wc -l)
pods=$(kubectl get pods --all-namespaces --no-headers | wc -l)
deployments=$(kubectl get deployments --all-namespaces --no-headers | wc -l)
services=$(kubectl get services --all-namespaces --no-headers | wc -l)
running_pods=$(kubectl get pods --all-namespaces --no-headers | grep -c "Running" || echo "0")

echo "Namespaces:     $namespaces"
echo "Nodes:          $nodes"
echo "Pods:           $pods (Running: $running_pods)"
echo "Deployments:    $deployments"
echo "Services:       $services"

# Calculate overall health score
total_checks=7
passed_checks=0
for service in "${!SERVICE_STATUS[@]}"; do
    if [[ "${SERVICE_STATUS[$service]}" == "✅" ]]; then
        ((passed_checks++))
    fi
done

health_percentage=$(( (passed_checks * 100) / total_checks ))

echo -e "\n${MAGENTA}🏆 OVERALL HEALTH SCORE: $passed_checks/$total_checks ($health_percentage%)${NC}"

if [[ $health_percentage -ge 90 ]]; then
    echo -e "${GREEN}🎉 EXCELLENT - Enterprise ready!${NC}"
elif [[ $health_percentage -ge 70 ]]; then
    echo -e "${YELLOW}⚠️ GOOD - Minor issues to address${NC}"
else
    echo -e "${RED}❌ NEEDS ATTENTION - Critical issues found${NC}"
fi

# Final updated summary
show_dynamic_summary

# 🥋 Chuck Norris for Closure
JOKE=$(curl -s https://api.chucknorris.io/jokes/random | jq -r '.value' 2>/dev/null || echo "Chuck Norris can validate Kubernetes clusters with his eyes closed!")
echo -e "\n🥋 Completed Live-Health Chuck: $JOKE"

# Final timestamp and success message
final_timestamp=$(date +"%Y-%m-%d %H:%M:%S %Z")
log_summary "SUCCESS" "✅ Step 'Cluster Health Check' completed."

echo -e "\n✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
echo "✅ Cluster Audit Complete — Long live Helix!"
echo "🕐 Completed at: $final_timestamp"
echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"

log_summary "SUCCESS" "$final_timestamp ✅ Step 'Cluster Health Check' completed."
