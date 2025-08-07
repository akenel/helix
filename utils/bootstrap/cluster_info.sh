#!/usr/bin/env bash
# 🧭 utils/bootstrap/cluster_info.sh
# — Displays current Kubernetes cluster context information.
# This script is intended to be sourced by other scripts.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Sourcing cluster_info.sh from $SCRIPT_DIR"
source "$SCRIPT_DIR/../core/spinner_utils.sh" || { echo "Failed to source spinner.sh"; exit 1; }
# --- Logging Utilities ---
if ! command -v log_info >/dev/null 2>&1; then
    log_info()    { echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S %Z') $1"; }
    log_success() { echo "[SUCCESS] $(date +'%Y-%m-%d %H:%M:%S %Z') $1"; }
    log_warn()    { echo "[WARN] $(date +'%Y-%m-%d %H:%M:%S %Z') $1" >&2; }
    log_error()   { echo "[ERROR] $(date +'%Y-%m-%d %H:%M:%S %Z') $1" >&2; }
fi
# --- Safe Kubectl/Helm Wrappercluster_names ---
safe_kubectl() {
    local timeout="${1:-3}"
    shift
    if ! command -v kubectl >/dev/null; then
        echo "kubectl not found"
        return 1
    fi
    timeout "$timeout" kubectl "$@" 2>/dev/null || echo "N/A (timeout or error)"
}
safe_helm() {
    local cmd="$1"
    local timeout="${2:-5}"
    if ! command -v helm >/dev/null; then echo "helm not found"; return 1; fi
    timeout "$timeout" helm $cmd 2>/dev/null || echo "N/A (timeout or error)"
}
# --- Cluster Connectivity ---
check_cluster_connectivity() {
    log_info "Checking cluster connectivity..."
    if timeout 30 kubectl cluster-info >/dev/null 2>&1; then
        log_success "Cluster is reachable"
        return 0
    else
        log_error "Cluster is not reachable or kubectl is not configured properly"
        return 1
    fi
}
# --- Main Cluster Info Display ---
cluster_info() {
    local HOST="${HOST_IP:-Unknown}"
    local CITY="${CITY:-Unknown}"
    local REGION="${REGION:-Unknown}"
    local COUNTRY="${COUNTRY:-Unknown}"
    local TEMP="${TEMP:-N/A}"
    local WIND="${WIND:-N/A}"
    local DOCKER="${DOCKER_VER:-Unknown}"
    local LINUX="${LINUX_INFO:-Unknown}"
    log_info "Host IP: ${HOST}"
    echo ""
    echo "✨ Grand Helix Platform Deployment 🚀"
    echo "🗓  $(date)"
    echo "📍 ${CITY}, ${REGION}, ${COUNTRY} — 🌤  ${TEMP}°C, Wind ${WIND} km/h"
    echo "🐳 Docker: ${DOCKER} • 🐧 Linux: ${LINUX}"
    echo "---------------------------------------------"
    if ! check_cluster_connectivity; then
      echo "❌ Cannot connect to Kubernetes cluster"
      echo "   Please check your kubeconfig and cluster status"
      echo "   Continuing anyway — please use the menu to create a cluster."
      echo "---------------------------------------------"
    else
      CLUSTER_CONNECTED=true
    fi
    echo "🔗 Cluster Information:"
    if [[ "${CLUSTER_CONNECTED:-false}" == true ]]; then
        echo "ℹ️ Checking kubectl context, cluster name, API server, health checks ..."
    else
        echo "🚀 Cluster details are unavailable until a cluster is created."
    fi
    echo "---------------------------------------------"
    local current_context
    local cluster_name
    local api_server
    local k8s_version
    local helm_version
# Avoid script exit on command error inside this function
    set +e
    current_context=$(kubectl config current-context 2>/dev/null || echo "N/A")
    cluster_name=$(kubectl config view -o jsonpath="{.clusters[0].name}" 2>/dev/null || echo "N/A")
    api_server=$(kubectl config view -o jsonpath="{.clusters[0].cluster.server}" 2>/dev/null || echo "N/A")
    set -e
    if k8s_version=$(safe_kubectl 5 version --short --output=json | jq -r '.serverVersion.gitVersion' 2>/dev/null); then
        :
    elif k8s_version=$(safe_kubectl 5 version --client --short | awk '{print $3}' 2>/dev/null); then
        k8s_version="$k8s_version (client only)"
    else
        k8s_version="N/A"
    fi
    helm_version=$(safe_helm "version --template '{{.Version}}'")
    echo "🔧 Cluster Context: ${current_context}"
    echo "🔗 Cluster Name: ${cluster_name}"
    echo "🔍 Cluster API Server: ${api_server}"
    echo "---------------------------------------------"
    echo "🌐 Kubernetes Version: ${k8s_version}"
    echo "🔗 Helm Version: ${helm_version}"
    echo "---------------------------------------------"
    echo "🏥 Cluster Health Check:"
    if node_count=$(safe_kubectl 5 get nodes --no-headers | wc -l 2>/dev/null); then
        echo "   🟢 Nodes: ${node_count} available"
    else
        echo "   ⚠️  Nodes: Unable to retrieve node information"
    fi
    if safe_kubectl 5 get ns kube-system >/dev/null 2>&1; then
        echo "   🟢 System Namespace: Accessible"
        if pod_count=$(safe_kubectl 5 get pods -n kube-system --no-headers | wc -l 2>/dev/null); then
            echo "   🟢 Pods in kube-system: ${pod_count} running"
        else
            echo "   ⚠️  Pods in kube-system: Unable to retrieve pod information"
        fi
    else
        echo "   ⚠️  System Namespace: Not accessible"
    fi
    echo ""
}
# --- Optional Smoke Tests ---
test_cluster_operations() {
    log_info "Testing basic cluster operations..."
    if safe_kubectl 5 get namespaces >/dev/null; then
        log_success "Can list namespaces"
    else
        log_error "Cannot list namespaces"
    fi
    if safe_kubectl 5 get pods -n default >/dev/null; then
        log_success "Can list pods in default namespace"
    else
        log_warn "Cannot list pods in default namespace (may be permissions)"
    fi
    if safe_kubectl 5 get services -n default >/dev/null; then
        log_success "Can list services in default namespace"
    else
        log_warn "Cannot list services in default namespace"
    fi
}
# --- Export for Sourcing ---
echo "Export for Sourcing cluster_info.sh from $SCRIPT_DIR"
export -f cluster_info
export -f check_cluster_connectivity
export -f test_cluster_operations
# --- Run Cluster Info ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cluster_info
    test_cluster_operations
else
    echo "cluster_info.sh sourced successfully. Use 'cluster_info' to display cluster information."
fi
echo "Exported functions: cluster_info, check_cluster_connectivity, test_cluster_operations"
export CLUSTER_CONNECTED="${CLUSTER_CONNECTED:-false}"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Cluster info script executed directly. Exiting with success."
    exit 0
else    
    echo "Cluster info script sourced successfully. Use 'cluster_info' to display cluster information."
fi
# Return 0 to indicate successful sourcing
echo "Cluster info script sourced successfully. Use 'cluster_info' to display cluster information."
export CLUSTER_CONNECTED="${CLUSTER_CONNECTED:-false}"