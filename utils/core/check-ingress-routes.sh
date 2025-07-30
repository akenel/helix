#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR

# Source common configuration and utility functions
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/spinner_utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/set-kubeconfig.sh" # Ensure kubectl context is set

log_info "Running Ingress Route checks..."

if ! kubectl config current-context &> /dev/null; then
    log_error "kubectl context is not set. Cannot run Ingress checks."
    exit 1
fi

# Check Adminer IngressRoute
ADMINER_HOST="adminer.helix" # From adminer-ingress-route.yaml
ADMINER_NAMESPACE="database-ui" # From the yaml
log_info "Checking Adminer IngressRoute ($ADMINER_HOST) in namespace $ADMINER_NAMESPACE..."
if kubectl get ingressroute -n "$ADMINER_NAMESPACE" adminer-ingress-route &> /dev/null; then
    if kubectl get ingressroute -n "$ADMINER_NAMESPACE" adminer-ingress-route -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
        log_success "Adminer IngressRoute ($ADMINER_HOST) is ready."
    else
        log_warn "Adminer IngressRoute ($ADMINER_HOST) is not yet ready."
    fi
else
    log_error "Adminer IngressRoute ($ADMINER_HOST) not found."
fi

# Check Portainer Ingress
PORTAINER_HOST="portainer.helix" # From portainer-ingress.yaml
PORTAINER_NAMESPACE="portainer" # From the yaml
log_info "Checking Portainer Ingress ($PORTAINER_HOST) in namespace $PORTAINER_NAMESPACE..."
if kubectl get ingress -n "$PORTAINER_NAMESPACE" portainer-ingress &> /dev/null; then
    if kubectl get ingress -n "$PORTAINER_NAMESPACE" portainer-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' &> /dev/null; then
        log_success "Portainer Ingress ($PORTAINER_HOST) is ready with an IP."
    else
        log_warn "Portainer Ingress ($PORTAINER_HOST) is not yet ready (no IP assigned)."
    fi
else
    log_error "Portainer Ingress ($PORTAINER_HOST) not found."
fi

log_success "Ingress Route checks complete."