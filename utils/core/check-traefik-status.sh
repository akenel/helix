#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/spinner_utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/set-kubeconfig.sh" # Ensure kubectl context is set

log_info "Running Traefik Ingress Controller status check..."

if ! kubectl config current-context &> /dev/null; then
    log_error "kubectl context is not set. Cannot check Traefik status."
    exit 1
fi

start_spinner "Checking Traefik Ingress Controller pods..."
if kubectl get pods -n traefik -l app.kubernetes.io/name=traefik --field-selector=status.phase=Running | grep -q "traefik"; then
    stop_spinner 0
    log_success "Traefik Ingress Controller pods are running."
else
    stop_spinner 1
    log_error "Traefik Ingress Controller pods are NOT running. Ingress might not work."
fi

log_success "Traefik status check complete."