#!/bin/bash
# \\wsl.localhost\Ubuntu\home\angel\helix_v3\utils\generate_core_tls_certs.sh
set -euo pipefail # Exit on error, unset variables, and pipeline errors
echo "⚡️ Starting bootstrap\utils\01b_generate_core_tls_certs.sh"
# --- Logging Functions ---
# These functions automatically add timestamps and log levels.
INFO() { echo "[$(date +'%Y-%m-%d %H:%M:%S %Z')] [INFO] $1"; }
SUCCESS() { echo "[$(date +'%Y-%m-%d %H:%M:%S %Z')] [SUCCESS] $1"; }
ERROR() { echo "[$(date +'%Y-%m-%d %H:%M:%S %Z')] [ERROR] $1" >&2; exit 1; }

# --- Configuration ---
# Fixed path to services.yaml file
SERVICES_CONFIG_FILE="./bootstrap/addon-configs/services.yaml"
ISSUER_NAME="mkcert-ca-issuer" # Your ClusterIssuer name

INFO "⚡️ Starting core TLS certificate generation for Helix platform services."

# --- Pre-requisite Checks ---

# Check for yq (YAML processor)
INFO "🔍 Checking for 'yq' (YAML processor) installation..."
if ! command -v yq &> /dev/null; then
    ERROR "yq (YAML processor) is not installed. Please install it (e.g., snap install yq, brew install yq) to parse the services.yaml file. Aborting."
fi
SUCCESS "'yq' is installed."

# Ensure cert-manager components are fully ready
INFO "⏳ Waiting for all cert-manager pods to be ready (cert-manager, webhook, cainjector)..."
for pod in cert-manager webhook cainjector; do
    pod_name=$(kubectl get pods -n cert-manager -l app.kubernetes.io/name=${pod} -o jsonpath="{.items[0].metadata.name}")
    if [ -z "$pod_name" ]; then
        ERROR "No running pod found for component '${pod}'"
    fi
    kubectl wait --for=condition=Ready pod/${pod_name} -n cert-manager --timeout=5m \
        || ERROR "Pod '${pod_name}' (${pod}) not ready after 5 minutes."
done
SUCCESS "All cert-manager pods are ready."
echo "🎯 Continuing further in bootstrap\utils\generate_core_tls_certs.sh"
# Ensure the ClusterIssuer is ready
INFO "⏳ Waiting for ClusterIssuer '${ISSUER_NAME}' to be ready..."
kubectl wait --for=condition=Ready clusterissuer/${ISSUER_NAME} --timeout=2m \
    || ERROR "ClusterIssuer '${ISSUER_NAME}' not ready after 2 minutes. Check 'kubectl get clusterissuer ${ISSUER_NAME}' for details."
SUCCESS "ClusterIssuer '${ISSUER_NAME}' is ready and operational."

# --- Namespace Pre-creation ---
INFO "Ensuring necessary namespaces exist for TLS secrets as defined in '${SERVICES_CONFIG_FILE}'..."
NAMESPACES=$(yq '.tls_services[].namespace' "${SERVICES_CONFIG_FILE}" | sort -u)
if [ -z "${NAMESPACES}" ]; then
    INFO "No namespaces defined in '${SERVICES_CONFIG_FILE}'. Skipping namespace creation."
else
    for ns in ${NAMESPACES}; do
        if kubectl get namespace "${ns}" &> /dev/null; then
            INFO "Namespace '${ns}' already exists. Skipping creation."
        else
            kubectl create namespace "${ns}" || ERROR "Failed to create namespace '${ns}'."
            SUCCESS "Namespace '${ns}' created."
        fi
    done
fi
INFO "All required namespaces are present."

# --- Certificate Generation Loop ---
INFO "🎯 Starting TLS certificate generation for all services defined in '${SERVICES_CONFIG_FILE}'..."

NUM_SERVICES=$(yq '.tls_services | length' "${SERVICES_CONFIG_FILE}")

if [ "${NUM_SERVICES}" -eq 0 ]; then
    INFO "No services found in '${SERVICES_CONFIG_FILE}' for TLS certificate generation. Skipping."
else
    for i in $(seq 0 $((NUM_SERVICES - 1))); do
        SERVICE_NAME=$(yq ".tls_services[${i}].name" "${SERVICES_CONFIG_FILE}")
        NAMESPACE=$(yq ".tls_services[${i}].namespace" "${SERVICES_CONFIG_FILE}")
        HOSTNAME=$(yq ".tls_services[${i}].hostname" "${SERVICES_CONFIG_FILE}")
        SECRET_NAME=$(yq ".tls_services[${i}].secret_name" "${SERVICES_CONFIG_FILE}")

        INFO "Processing certificate for Service: '${SERVICE_NAME}' (Namespace: '${NAMESPACE}', Hostname: '${HOSTNAME}', Secret: '${SECRET_NAME}')..."

        # Handle multiple DNS names if you extend your YAML structure
        DNS_NAMES="${HOSTNAME}"
        # Example for multiple hostnames from YAML:
        # if yq ".tls_services[${i}].additional_hostnames" "${SERVICES_CONFIG_FILE}" &> /dev/null; then
        #     ADDITIONAL_HOSTNAMES=$(yq ".tls_services[${i}].additional_hostnames[]" "${SERVICES_CONFIG_FILE}")
        #     for h in ${ADDITIONAL_HOSTNAMES}; do
        #         DNS_NAMES="${DNS_NAMES}\n    - ${h}"
        #     done
        # fi

        cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${SERVICE_NAME}-tls-cert # Using service name for Certificate resource name for clarity
  namespace: ${NAMESPACE}
spec:
  secretName: ${SECRET_NAME} # The specific secret name defined in YAML
  issuerRef:
    name: ${ISSUER_NAME}
    kind: ClusterIssuer
  dnsNames:
    - ${DNS_NAMES}
EOF

        INFO "⏳ Waiting for '${SERVICE_NAME}' certificate ('${SERVICE_NAME}-tls-cert') in namespace '${NAMESPACE}' to be ready. This may take a moment..."
        # Add a more generous timeout for certificate issuance, especially on first run or busy clusters
        kubectl wait --for=condition=Ready certificate/${SERVICE_NAME}-tls-cert -n "${NAMESPACE}" --timeout=7m \
            || ERROR "${SERVICE_NAME} certificate did not become ready in 7 minutes. Check 'kubectl describe certificate ${SERVICE_NAME}-tls-cert -n ${NAMESPACE}' for errors."
        SUCCESS "${SERVICE_NAME} TLS secret '${NAMESPACE}/${SECRET_NAME}' is ready."
    done
fi

INFO "✅ All core TLS certificate requests submitted and secrets confirmed ready."
echo "✅ Completed bootstrap\utils\generate_core_tls_certs.sh"
SUCCESS "✅ TLS certificate generation process completed successfully for all defined services."