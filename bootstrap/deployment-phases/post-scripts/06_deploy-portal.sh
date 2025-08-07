#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR
# 🧠 Helix Sherlock Bootstrap — bootstrap/06_deploy-portal.sh

shopt -s failglob
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HELIX_ROOT_DIR="$SCRIPT_DIR"
# ─────── Load Utility Functions ───────────────────────
source "${HELIX_ROOT_DIR}/utils/core/config.sh" # For HELIX_BOOTSTRAP_DIR if needed
source "${HELIX_ROOT_DIR}/utils/core/spinner_utils.sh" # For log_info, log_success, log_error, start_spinner, stop_spinner
source "${HELIX_ROOT_DIR}/utils/set-kubeconfig.sh" # To ensure kubectl context is set

# ─────── Configuration Variables ──────────────────────
PORTAL_NAMESPACE="default"
PORTAL_HOSTNAME="portal.helix"
PORTAL_CONFIG_DIR="${SCRIPT_DIR}/configs/portal"
PORTAL_CONFIGMAP_NAME="helix-portal-html"
PORTAL_DEPLOYMENT_YAML="${PORTAL_CONFIG_DIR}/portal-deployment.yaml"
PORTAL_SERVICE_YAML="${PORTAL_CONFIG_DIR}/portal-service.yaml"
PORTAL_INGRESSROUTE_YAML="${PORTAL_CONFIG_DIR}/portal-ingressroute.yaml"
PORTAL_CERT_NAME="portal-tls-cert" # New certificate for the portal
PORTAL_SECRET_NAME="helix-portal-tls-secret" # Secret where the portal cert will be stored

# ─────── Functions ────────────────────────────────────

# Function to generate the dynamic HTML content
generate_portal_html() {
  log_info "Generating dynamic HTML for the Helix Portal..."

  # Define your service URLs. These should match your IngressRoute hostnames.
  # Use the .helix suffix for local development.
  local KEYCLOAK_URL="https://keycloak.helix"
  local VAULT_URL="https://vault.helix"
  local PORTAINER_URL="https://portainer.helix"
  local ADMINER_URL="https://adminer.helix"
  local KONG_URL="https://kong.helix"
  local TRAEFIK_DASHBOARD_URL="https://traefik.helix/dashboard/"

  # Build the HTML links dynamically
  local SERVICE_LINKS_HTML=""
  SERVICE_LINKS_HTML+="<a href=\"${KEYCLOAK_URL}\" target=\"_blank\" class=\"block bg-blue-600 hover:bg-blue-700 text-white font-bold py-3 px-6 rounded-lg transition duration-300 ease-in-out transform hover:scale-105 shadow-lg\">🔑 Keycloak Identity Hub</a>"
  SERVICE_LINKS_HTML+="<a href=\"${VAULT_URL}\" target=\"_blank\" class=\"block bg-purple-600 hover:bg-purple-700 text-white font-bold py-3 px-6 rounded-lg transition duration-300 ease-in-out transform hover:scale-105 shadow-lg\">🔒 Vault Secrets Management</a>"
  SERVICE_LINKS_HTML+="<a href=\"${PORTAINER_URL}\" target=\"_blank\" class=\"block bg-green-600 hover:bg-green-700 text-white font-bold py-3 px-6 rounded-lg transition duration-300 ease-in-out transform hover:scale-105 shadow-lg\">🐳 Portainer Container Management</a>"
  SERVICE_LINKS_HTML+="<a href=\"${ADMINER_URL}\" target=\"_blank\" class=\"block bg-yellow-600 hover:bg-yellow-700 text-white font-bold py-3 px-6 rounded-lg transition duration-300 ease-in-out transform hover:scale-105 shadow-lg\">🐘 Adminer Database UI</a>"
  SERVICE_LINKS_HTML+="<a href=\"${KONG_URL}\" target=\"_blank\" class=\"block bg-red-600 hover:bg-red-700 text-white font-bold py-3 px-6 rounded-lg transition duration-300 ease-in-out transform hover:scale-105 shadow-lg\">🚦 Kong API Gateway</a>"
  SERVICE_LINKS_HTML+="<a href=\"${TRAEFIK_DASHBOARD_URL}\" target=\"_blank\" class=\"block bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-3 px-6 rounded-lg transition duration-300 ease-in-out transform hover:scale-105 shadow-lg\">📈 Traefik Dashboard</a>"
  
  # Add other services as you deploy them (e.g., Kafka UI, n8n, Minio)
  # SERVICE_LINKS_HTML+="<a href=\"https://kafka-ui.helix\" target=\"_blank\" class=\"block bg-orange-600 hover:bg-orange-700 text-white font-bold py-3 px-6 rounded-lg transition duration-300 ease-in-out transform hover:scale-105 shadow-lg\">📊 Kafka UI</a>"
  # SERVICE_LINKS_HTML+="<a href=\"https://n8n.helix\" target=\"_blank\" class=\"block bg-teal-600 hover:bg-teal-700 text-white font-bold py-3 px-6 rounded-lg transition duration-300 ease-in-out transform hover:scale-105 shadow-lg\">⚙️ n8n Workflow Automation</a>"
  # SERVICE_LINKS_HTML+="<a href=\"https://minio.helix\" target=\"_blank\" class=\"block bg-gray-600 hover:bg-gray-700 text-white font-bold py-3 px-6 rounded-lg transition duration-300 ease-in-out transform hover:scale-105 shadow-lg\">☁️ Minio Object Storage</a>"

  # The full HTML template
  cat <<EOF > /tmp/helix-portal-index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Helix Platform Portal</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        body { font-family: 'Inter', sans-serif; }
    </style>
</head>
<body class="bg-gray-900 text-gray-100 min-h-screen flex items-center justify-center p-4">
    <div class="bg-gray-800 p-8 rounded-xl shadow-2xl max-w-2xl w-full text-center">
        <h1 class="text-4xl font-bold text-blue-400 mb-6">Welcome to Helix Platform!</h1>
        <p class="text-lg text-gray-300 mb-8">
            Click on a service below to access it.
        </p>
        <div id="service-links" class="space-y-4">
            ${SERVICE_LINKS_HTML}
        </div>
        <p class="mt-8 text-sm text-gray-500">
            Powered by Helix Bootstrap & Kubernetes
        </p>
    </div>
</body>
</html>
EOF
  log_success "HTML content generated at /tmp/helix-portal-index.html"
}

# ─────── Main Deployment Logic ────────────────────────
log_info "🚀 Starting Helix Portal deployment..."

# Ensure kubectl context is set
# Ensure kubectl context is set
# Ensure kubectl context is set by calling the sourced function
start_spinner "Setting kubectl context..."
if ! _set_kubeconfig_env; then # Call the function, check its return status
    stop_spinner 1 # Indicate failure to the spinner
    log_error "Failed to set kubectl context. Exiting portal deployment."
    exit 1 # Exit 06_deploy-portal.sh if context setting failed
fi
stop_spinner 0 # Indicate success to the spinner
log_success "kubectl context set."

if ! kubectl config current-context &> /dev/null; then
    log_error "kubectl context is still not set after attempting to configure. Cannot proceed with Portal deployment."
    exit 1
fi
log_info "Using kubectl context: $(kubectl config current-context)"


# Ensure the portal namespace exists
log_info "Ensuring namespace '${PORTAL_NAMESPACE}' exists..."
start_spinner "Applying namespace..."
if ! kubectl get namespace "${PORTAL_NAMESPACE}" > /dev/null 2>&1; then
    kubectl create namespace "${PORTAL_NAMESPACE}" > /dev/null 2>&1
fi
stop_spinner $?
log_success "Namespace '${PORTAL_NAMESPACE}' ensured."

# 1. Generate the dynamic HTML content
generate_portal_html

# 2. Create/Update the ConfigMap with the generated HTML
log_info "Creating/Updating ConfigMap '${PORTAL_CONFIGMAP_NAME}'..."
start_spinner "Applying ConfigMap..."
if kubectl create configmap "${PORTAL_CONFIGMAP_NAME}" --from-file=/tmp/helix-portal-index.html -n "${PORTAL_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1; then
    stop_spinner $?
    log_success "ConfigMap '${PORTAL_CONFIGMAP_NAME}' updated successfully."
else
    stop_spinner $?
    log_error "Failed to create/update ConfigMap '${PORTAL_CONFIGMAP_NAME}'."
    exit 1
fi

# 3. Issue a new TLS certificate for portal.helix
log_info "Requesting TLS certificate for '${PORTAL_HOSTNAME}' in namespace '${PORTAL_NAMESPACE}'..."
start_spinner "Applying Certificate resource..."
cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${PORTAL_CERT_NAME}
  namespace: ${PORTAL_NAMESPACE}
spec:
  secretName: ${PORTAL_SECRET_NAME}
  duration: 2160h # 90d
  renewBefore: 360h # 15d
  dnsNames:
    - ${PORTAL_HOSTNAME}
  issuerRef:
    name: mkcert-ca-issuer
    kind: ClusterIssuer
EOF
stop_spinner $?
log_success "Certificate request for '${PORTAL_HOSTNAME}' submitted."

log_info "Waiting for TLS secret '${PORTAL_SECRET_NAME}' to be ready..."
start_spinner "Waiting for certificate readiness..."
if ! kubectl wait --for=condition=Ready certificate/${PORTAL_CERT_NAME} -n "${PORTAL_NAMESPACE}" --timeout=300s > /dev/null 2>&1; then
    stop_spinner 1
    log_error "TLS certificate for '${PORTAL_HOSTNAME}' did not become ready in time."
    exit 1
fi
stop_spinner 0
log_success "TLS secret '${PORTAL_SECRET_NAME}' is ready."


# 4. Apply Portal Deployment, Service, and IngressRoute
log_info "Applying Portal Deployment, Service, and IngressRoute..."

start_spinner "Applying Deployment..."
if kubectl apply -f "${PORTAL_DEPLOYMENT_YAML}" -n "${PORTAL_NAMESPACE}" > /dev/null 2>&1; then
    stop_spinner $?
    log_success "Portal Deployment applied."
else
    stop_spinner $?
    log_error "Failed to apply Portal Deployment."
    exit 1
fi

start_spinner "Applying Service..."
if kubectl apply -f "${PORTAL_SERVICE_YAML}" -n "${PORTAL_NAMESPACE}" > /dev/null 2>&1; then
    stop_spinner $?
    log_success "Portal Service applied."
else
    stop_spinner $?
    log_error "Failed to apply Portal Service."
    exit 1
fi

start_spinner "Applying IngressRoute..."
# Before applying IngressRoute, ensure the secret it references is in the same namespace.
# If helix-tls-cert is only in other namespaces, we need to copy it or issue a new one.
# We just issued a new one for portal.helix specifically. So the IngressRoute should reference PORTAL_SECRET_NAME.
# Let's modify the IngressRoute YAML to use the newly created secret.
# This requires a temporary modification or dynamic generation of the IngressRoute.
# For simplicity, let's just use sed to replace the secretName in the template.
cp "${PORTAL_INGRESSROUTE_YAML}" /tmp/portal-ingressroute-temp.yaml
sed -i "s|secretName: helix-tls-cert|secretName: ${PORTAL_SECRET_NAME}|g" /tmp/portal-ingressroute-temp.yaml
sed -i "s|Host(\`portal.helix\`)|Host(\`${PORTAL_HOSTNAME}\`)|g" /tmp/portal-ingressroute-temp.yaml

if kubectl apply -f /tmp/portal-ingressroute-temp.yaml -n "${PORTAL_NAMESPACE}" > /dev/null 2>&1; then
    stop_spinner $?
    log_success "Portal IngressRoute applied."
else
    stop_spinner $?
    log_error "Failed to apply Portal IngressRoute."
    exit 1
fi
rm /tmp/portal-ingressroute-temp.yaml # Clean up temp file

# 5. Wait for Portal Pod to be ready
log_info "Waiting for Helix Portal pod to be running..."
start_spinner "Waiting for pod..."
if ! kubectl wait --for=condition=Ready pod -l app=helix-portal -n "${PORTAL_NAMESPACE}" --timeout=300s > /dev/null 2>&1; then
    stop_spinner 1
    log_error "Helix Portal pod did not become ready in time."
    exit 1
fi
stop_spinner 0
log_success "Helix Portal pod is running."

log_success "Helix Portal deployment complete. Access at: https://${PORTAL_HOSTNAME}"