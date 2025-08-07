#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR

# === Global Flags ===
DRY_RUN=false
VERBOSE=false

# Ensure correct kubeconfig is used
export KUBECONFIG="${KUBECONFIG:-$HOME/.helix/kubeconfig.yaml}"
kubectl config use-context helix >/dev/null 2>&1 || {
  echo "❌ Unable to connect to Kubernetes API. Check kubeconfig or cluster status."
  exit 1
}
# === Configuration Variables (Defaults, can be overridden) ===
SERVICE=""
CLUSTER_NAME="" # New: To be discovered or prompted
DOMAIN=""
NAMESPACE="" # Changed: To be discovered or prompted
SECRET_NAME=""
DEPLOYMENT_NAME=""
K8S_RESOURCE_TYPE="deployment" # Default, can be 'statefulset'
CERT_DIR=""
INGRESS_NAME=""
PORT="" # Kubernetes service port
# === Logging Functions ===
log_info() { echo -e "[INFO] $*"; }
log_success() { echo -e "\e[32m[SUCCESS]\e[0m $*"; }
log_error() { echo -e "\e[31m[ERROR]\e[0m $*"; }
log_warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
log_step() { echo -e "\n--- $* ---"; }
log_debug() { $VERBOSE && echo -e "\e[36m[DEBUG]\e[0m $*"; }

# === Command Wrapper ===
run_cmd() {
    local cmd="$*"
    if $VERBOSE || $DRY_RUN; then
        echo "[CMD] $cmd"
    fi
    if $DRY_RUN; then
        return 0
    fi
    # Use eval to handle complex commands with quotes, but be mindful of security
    # Added stderr redirection to /dev/null for cleaner output unless VERBOSE is true
    if $VERBOSE; then
        eval "$cmd"
    else
        eval "$cmd" 2>/dev/null
    fi
}

# === Argument Parsing ===
while [[ $# -gt 0 ]]; do
    case $1 in
        --service-name)
            SERVICE="$2"
            shift 2
            ;;
        --cluster-name) # New argument
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --namespace) # New argument
            NAMESPACE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 --service-name <name> [--cluster-name <name>] [--namespace <name>] [--dry-run] [--verbose]"
            echo ""
            echo "Options:"
            echo "  --service-name   Name of the Kubernetes service (required)"
            echo "  --cluster-name   Target K3d cluster name (e.g., 'helix'). If omitted and only one k3d cluster exists, it's used. Otherwise, user is prompted."
            echo "  --namespace      Target Kubernetes namespace. If omitted, script attempts to guess or prompts user."
            echo "  --dry-run        Simulate all steps without making changes"
            echo "  --verbose        Show detailed logs and executed commands"
            echo "  --help, -h       Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# === Utility Functions ===

# kubectl_cmd wrapper with --validate=false for local resource schema validation
# AND --insecure-skip-tls-verify for API server TLS connection issues (essential for local k3d/WSL)
# This function is crucial for all kubectl interactions.
kubectl_cmd() {
    local cmd_str="kubectl $*"   # Original command string for logging
    local kubectl_args=("$@")    # Store arguments in array

    if $VERBOSE || $DRY_RUN; then
        echo "[KUBECTL] $cmd_str" >&2   # Send diagnostics to stderr
    fi
    if $DRY_RUN; then
        return 0
    fi

    # Add --validate=false for apply/create commands using -f
    if [[ "$cmd_str" =~ (apply|create).*-f ]]; then
        kubectl_args+=( "--validate=false" )
    fi

    # Add --insecure-skip-tls-verify for local clusters (safe only for dev!)
    kubectl_args+=( "--insecure-skip-tls-verify" )

    # Fire the command like a bullet — no extra echoes
    kubectl "${kubectl_args[@]}"
}

# New function to ensure kubectl is authenticated
ensure_kubectl_login() {
    log_info "Verifying kubectl authentication by attempting 'kubectl get nodes'..."
    if ! kubectl_cmd get nodes >/dev/null; then
        log_error "Failed to authenticate with Kubernetes cluster. 'kubectl get nodes' failed. This indicates a core issue with your kubeconfig or network connectivity."
        log_error "Please ensure your k3d cluster is running and your kubeconfig is correctly set up."
        return 1
    fi
    log_success "Kubectl authenticated successfully. ✅"
    return 0
}


fix_k3d_kubeconfig_server_address() {
    local kubeconfig="${KUBECONFIG:-$HOME/.kube/config}"
    if grep -q "host.docker.internal" "$kubeconfig"; then
        echo "[INFO] Patching kubeconfig: replacing 'host.docker.internal' with '127.0.0.1'..." >&2
        sed -i 's/host\.docker\.internal/127\.0\.0\.1/g' "$kubeconfig"
        # kubectl get nodes is a good way to test connectivity after patching
        if kubectl_cmd get nodes &>/dev/null; then
            echo "[SUCCESS] Kubeconfig server address updated and connectivity confirmed. 🛠️" >&2
        else
            echo "[WARN] Kubeconfig server address updated, but initial connectivity check failed. Proceeding, but monitor." >&2
        fi
    else
        echo "[INFO] Kubeconfig server address already set to 127.0.0.1/localhost. ✅" >&2
    fi

    # Double check and fix if it's still not 127.0.0.1
    local current_cluster_context="$(kubectl config current-context)"
    local target_cluster_name="${CLUSTER_NAME}" # Derive from CLUSTER_NAME
    
    # Only attempt to fix if CLUSTER_NAME is set and context matches
    if [[ -n "$CLUSTER_NAME" && "$current_cluster_context" == "$target_cluster_name" ]]; then
        local VALID_URL=$(kubectl config view -o=jsonpath="{.clusters[?(@.name==\"${target_cluster_name}\")].cluster.server}")
        if [[ "$VALID_URL" != https://127.0.0.1:* ]]; then
            log_warn "❌ kubeconfig server URL ($VALID_URL) for context '${target_cluster_name}' is invalid. Fixing..."
            # Get the current port, assuming it's part of the invalid URL or a default
            local current_port=$(echo "$VALID_URL" | sed -E 's/https:\/\/127\.0\.0\.1:([0-9]+)/\1/')
            # Fallback if port isn't extracted or is empty
            if [[ -z "$current_port" ]]; then
                current_port="6443" # Common default for Kubernetes API server
            fi
            # Use kubectl_cmd for setting the cluster, so it respects dry-run/verbose if applicable
            if ! kubectl_cmd config set-cluster "$target_cluster_name" --server="https://127.0.0.1:${current_port}"; then
                log_error "Failed to fix kubeconfig server address for cluster '${target_cluster_name}'."
                return 1
            fi
            log_success "✅ kubeconfig server URL fixed for '${target_cluster_name}' to https://127.0.0.1:${current_port}."
        fi
    elif [[ -z "$CLUSTER_NAME" ]]; then
        log_warn "CLUSTER_NAME not set yet, skipping specific kubeconfig URL validation. This will be re-evaluated after cluster discovery."
    else
        log_info "Current kubectl context '${current_cluster_context}' does not match target cluster '${target_cluster_name}'. Skipping specific kubeconfig URL validation."
    fi

    return 0
}


apply_secret_manager_rbac() {
    local namespace="${1:-default}"
    # The K3d default user is often 'admin@<cluster-name>'.
    # We should derive this from CLUSTER_NAME for accuracy.
    local user="admin@${CLUSTER_NAME}"

    if $DRY_RUN; then
        log_info "(Dry-run) Would apply RBAC Role and RoleBinding for secret management in namespace '${namespace}' for user '${user}'."
        return 0
    fi

    log_info "Applying RBAC Role and RoleBinding for secret management in namespace '${namespace}' for user '${user}'..."

    # Apply the Role using kubectl_cmd
    cat <<EOF | kubectl_cmd apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-manager
  namespace: ${namespace}
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "create", "update", "patch", "delete"] # Added "delete" for completeness
EOF

    # Check if Role application was successful
    if [[ $? -ne 0 ]]; then
        log_error "Failed to apply RBAC Role 'secret-manager' in namespace '${namespace}'. Aborting RBAC setup."
        return 1
    fi

    # Apply the RoleBinding using kubectl_cmd
    cat <<EOF | kubectl_cmd apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: secret-manager-binding
  namespace: ${namespace}
subjects:
- kind: User
  name: ${user}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: secret-manager
  apiGroup: rbac.authorization.k8s.io
EOF

    # Check if RoleBinding application was successful
    if [[ $? -ne 0 ]]; then
        log_error "Failed to apply RBAC RoleBinding 'secret-manager-binding' in namespace '${namespace}'. Aborting RBAC setup."
        return 1
    fi

    log_success "RBAC Role and Binding for '${user}' in '${namespace}' applied. ✅"
    return 0
}


wait_with_dots() {
    local message="$1"
    local seconds="$2"

    echo -n "$message"
    for ((i = 0; i < seconds; i++)); do
        echo -n "."
        sleep 1
    done
    echo ""
}

start_walker_spinner() {
    local frames=("🚶" "🏃" "🧍" "🧎")
    local i=0
    # Store current cursor position
    tput sc
    while true; do
        # Restore cursor, clear line, print spinner
        tput rc; tput el
        printf "🚀 Deploying service... ${frames[i]} "
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.3
    done
}

stop_spinner() {
    local SPINNER_PID=$1
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" >/dev/null 2>&1 || true
        wait "$SPINNER_PID" 2>/dev/null || true # Wait for spinner to terminate
        tput rc; tput el # Restore cursor and clear the spinner line
    fi
}

# Function to discover and set cluster and namespace
discover_cluster_and_namespace() {
    log_step "Discovering Cluster and Namespace"

    # 1. Discover CLUSTER_NAME
    if [[ -z "$CLUSTER_NAME" ]]; then
        local k3d_clusters=($(k3d cluster list -o json | jq -r '.[].name'))
        local num_clusters=${#k3d_clusters[@]}

        if [[ $num_clusters -eq 0 ]]; then
            log_error "No k3d clusters found. Please create a k3d cluster first (e.g., 'k3d cluster create mycluster')."
            return 1
        elif [[ $num_clusters -eq 1 ]]; then
            CLUSTER_NAME="${k3d_clusters[0]}"
            log_info "Found single k3d cluster: '${CLUSTER_NAME}'. Using this as default."
        else
            log_warn "Multiple k3d clusters found:"
            for i in "${!k3d_clusters[@]}"; do
                log_warn "  $((i+1)). ${k3d_clusters[$i]}"
            done
            read -rp "Please enter the target k3d cluster name: " CLUSTER_NAME
            if [[ -z "$CLUSTER_NAME" ]]; then
                log_error "No cluster name provided. Aborting."
                return 1
            fi
            # Validate if entered cluster name exists
            if ! printf '%s\n' "${k3d_clusters[@]}" | grep -q -w "$CLUSTER_NAME"; then
                log_error "Cluster '${CLUSTER_NAME}' not found. Please choose from the list."
                return 1
            fi
        fi
    else
        log_info "Using specified cluster: '${CLUSTER_NAME}'."
    fi

    # Set kubectl context to the discovered/selected cluster
    local KUBE_CONTEXT="${CLUSTER_NAME}"
    if ! kubectl config use-context "$KUBE_CONTEXT" &>/dev/null; then
        log_error "Failed to set kubectl context to '${KUBE_CONTEXT}'. Ensure the cluster exists and kubeconfig is correct."
        return 1
    fi
    log_success "Kubectl context set to '${KUBE_CONTEXT}'. ✅"

    # --- NEW: Ensure kubectl is authenticated immediately after context is set ---
    if ! ensure_kubectl_login; then
        log_error "Authentication to Kubernetes cluster failed after context switch. Cannot proceed."
        return 1
    fi
    # --- END NEW ---

    # 2. Discover NAMESPACE
    if [[ -z "$NAMESPACE" ]]; then
        log_info "Attempting to determine service namespace..."
        # Common service-specific namespaces
        case "$SERVICE" in
            "portainer")
                NAMESPACE="portainer"
                ;;
            "vault")
                NAMESPACE="vault"
                ;;
            "traefik")
                NAMESPACE="kube-system" # Traefik in k3d is often in kube-system by default
                ;;
            *)
                # Try to find a namespace matching the service name
                if kubectl_cmd get namespace "$SERVICE" &>/dev/null; then
                    NAMESPACE="$SERVICE"
                    log_info "Found namespace matching service name: '${NAMESPACE}'."
                else
                    # Fallback to default, then prompt if needed
                    NAMESPACE="default"
                    log_warn "Could not determine a specific namespace for '${SERVICE}'. Defaulting to '${NAMESPACE}'."
                    # Offer to list and prompt if desired
                    if ! $DRY_RUN; then
                        read -rp "Do you want to specify a different namespace? (y/N): " response
                        if [[ "$response" =~ ^[Yy]$ ]]; then
                            log_info "Available namespaces:"
                            kubectl_cmd get namespaces -o custom-columns=NAME:.metadata.name
                            read -rp "Please enter the target namespace: " new_namespace
                            if kubectl_cmd get namespace "$new_namespace" &>/dev/null; then
                                NAMESPACE="$new_namespace"
                                log_info "Using specified namespace: '${NAMESPACE}'."
                            else
                                log_error "Namespace '${new_namespace}' not found. Using 'default'."
                                NAMESPACE="default"
                            fi # This 'fi' closes the inner 'if kubectl_cmd get namespace "$new_namespace"'
                        fi # This 'fi' closes the 'if [[ "$response" =~ ^[Yy]$ ]]'
                    fi # This 'fi' closes the 'if ! $DRY_RUN; then'
                fi # This 'fi' closes the 'if kubectl_cmd get namespace "$SERVICE"'
                ;;
        esac # This 'esac' closes the 'case "$SERVICE"'
    else
        # Validate provided namespace
        if ! kubectl_cmd get namespace "$NAMESPACE" &>/dev/null; then
            log_error "Specified namespace '${NAMESPACE}' does not exist. Please create it or choose an existing one."
            return 1
        fi
        log_info "Using specified namespace: '${NAMESPACE}'."
    fi # This 'fi' closes the 'if [[ -z "$NAMESPACE" ]]'

    # --- Crucial Placement for RBAC ---
    # After the cluster context is established AND kubectl is confirmed to be authenticated,
    # apply RBAC for the current user/cluster.
    if ! apply_secret_manager_rbac "${NAMESPACE:-default}"; then # Pass a default namespace if not yet determined
        log_error "Failed to apply necessary RBAC permissions. This will likely cause further 'Unauthorized' errors."
        return 1
    fi
    # --- End Crucial Placement ---

    log_success "Namespace set to '${NAMESPACE}'. ✅"
    return 0
}


# Function to perform certificate generation and WSL trust setup
setup_wsl_certs() {
    log_step "Setting up WSL certs (coded)"
    log_info "Navigating to certificate directory: ${CERT_DIR}"
    mkdir -p "${CERT_DIR}" || { log_error "Failed to create directory ${CERT_DIR}. Check permissions."; return 1; }

    pushd "${CERT_DIR}" > /dev/null || { log_error "Failed to change to directory ${CERT_DIR}."; return 1; }

    # Clean up any existing mkcert CA in this directory and system store
    if [[ -f "ca.crt" ]]; then
        log_info "Removing old ca.crt from ${PWD}."
        rm -f "ca.crt"
    fi

    log_info "Attempting to uninstall any previous mkcert local CA from system trust stores..."
    # mkcert -uninstall can sometimes fail if no CA is installed, ignore errors
    run_cmd "mkcert -uninstall" || true
    log_success "Previous mkcert CA uninstalled (if present). 👍"

    log_info "Installing a brand new mkcert local CA..."
    run_cmd "mkcert -install" || { log_error "Failed to install new mkcert local CA."; return 1; }
    log_success "Brand new mkcert local CA installed successfully. 🚀"

    MKCERT_CA_PATH="$(mkcert -CAROOT 2>/dev/null)/rootCA.pem"
    if [[ ! -f "$MKCERT_CA_PATH" ]]; then
        log_error "Could not find the newly generated mkcert root CA at: ${MKCERT_CA_PATH}. Unexpected error."
        return 1
    fi

    log_info "Copying the new mkcert root CA to ${PWD}/ca.crt from ${MKCERT_CA_PATH}."
    if $DRY_RUN; then
        echo "[CMD] cp \"${MKCERT_CA_PATH}\" \"./ca.crt\""
        # In dry-run, create a dummy ca.crt so subsequent checks don't fail
        echo "---BEGIN CERTIFICATE---" > "./ca.crt"
        echo "---END CERTIFICATE---" >> "./ca.crt"
    else
        cp "${MKCERT_CA_PATH}" "./ca.crt" || { log_error "Failed to copy the new CA certificate to current directory."; return 1; }
    fi
    log_success "New root CA available as ca.crt in ${PWD}. ✅"

    log_info "Generating service certificate for *.${DOMAIN} AND ${DOMAIN} using the new mkcert CA..."
    run_cmd "mkcert -cert-file \"${DOMAIN}.crt\" -key-file \"${DOMAIN}.key\" \"*.${DOMAIN}\" \"${DOMAIN}\"" || { log_error "Failed to generate certificates for ${DOMAIN}."; return 1; }
    log_success "Certificates generated: ${DOMAIN}.crt and ${DOMAIN}.key. 🎉"

    log_info "Verifying ca.crt format (should be PEM)..."
    if ! head -n 1 "./ca.crt" | grep -q "BEGIN CERTIFICATE"; then
        log_error "ca.crt is not in PEM format. This script expects PEM. Manual intervention required."
        return 1
    fi
    log_success "ca.crt confirmed to be in PEM format. ✅"

    log_info "Adding the new ca.crt to WSL system trust store..."
    run_cmd "sudo cp \"./ca.crt\" \"/usr/local/share/ca-certificates/mkcert-${SERVICE}.crt\"" || { log_error "Failed to copy CA to WSL system store."; return 1; }
    run_cmd "sudo update-ca-certificates" || { log_error "Failed to update WSL system CA certificates."; return 1; }
    log_success "New CA certificate added to WSL system trust store. 🔐"

    popd > /dev/null # Go back to original directory
    return 0
}

# Function to discover service details and set domain
discover_service_details() {
    log_step "Discovering service details"

    # Set common variables based on SERVICE name
    # DOMAIN will now be set after CLUSTER_NAME is determined
    SECRET_NAME="${SERVICE}-tls"
    DEPLOYMENT_NAME="${SERVICE}" # Often the deployment/statefulset name matches service
    INGRESS_NAME="${SERVICE}-ingress" # Standard naming convention for ingress
    CERT_DIR="./certs/${SERVICE}"

    # Determine K8s resource type and service port based on SERVICE
    case "$SERVICE" in
        "portainer")
            K8S_RESOURCE_TYPE="deployment"
            PORT="9000" # Default Portainer UI port
            ;;
        "vault")
            K8S_RESOURCE_TYPE="statefulset" # Vault is often a StatefulSet
            PORT="8200" # Default Vault UI port
            ;;
        "traefik")
            K8S_RESOURCE_TYPE="deployment"
            PORT="8000" # Traefik dashboard default, or whatever your service exposes
            ;;
        *)
            # Default for services not explicitly handled
            K8S_RESOURCE_TYPE="deployment"
            # Attempt to find the port dynamically, or use a common default
            log_warn "Service '$SERVICE' not explicitly defined. Attempting to discover port or defaulting to 80."
            # Try to get the port from the K8s service
            # Note: This kubectl_cmd needs NAMESPACE to be set already
            PORT=$(kubectl_cmd get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="http" || @.name=="https" || @.name=="web" || @.name=="websecure")].port}' 2>/dev/null)
            if [[ -z "$PORT" ]]; then
                PORT="80" # Fallback if dynamic discovery fails
                log_warn "Could not dynamically determine port for '$SERVICE'. Defaulting to $PORT. Please verify."
            else
                log_info "Discovered port $PORT for service '$SERVICE'."
            fi
            ;;
    esac

    # Now that CLUSTER_NAME is set, define the DOMAIN
    if [[ -z "$CLUSTER_NAME" ]]; then
        log_error "CLUSTER_NAME is not set. Cannot determine DOMAIN. This is a script logic error."
        return 1
    fi
    DOMAIN="${SERVICE}.${CLUSTER_NAME}" # e.g., portainer.helix

    log_debug "SERVICE=$SERVICE"
    log_debug "DOMAIN=$DOMAIN"
    log_debug "NAMESPACE=$NAMESPACE"
    log_debug "SECRET_NAME=$SECRET_NAME"
    log_debug "DEPLOYMENT_NAME=$DEPLOYMENT_NAME"
    log_debug "K8S_RESOURCE_TYPE=$K8S_RESOURCE_TYPE"
    log_debug "CERT_DIR=$CERT_DIR"
    log_debug "INGRESS_NAME=$INGRESS_NAME"
    log_debug "PORT=$PORT"

    # Create cert directory *after* CERT_DIR is set
    mkdir -p "$CERT_DIR"

    return 0
}


check_service_endpoints() {
    log_step "Checking service endpoints (coded)"
    log_info "Attempting to verify the Kubernetes service '${SERVICE}' is accessible in namespace '${NAMESPACE}'..."

    # Check if the K8s service exists
    if ! kubectl_cmd get service "$SERVICE" -n "$NAMESPACE" &>/dev/null; then
        log_error "Service '${SERVICE}' not found in namespace '${NAMESPACE}'. Please ensure the service is deployed."
        return 1
    fi
    log_success "Kubernetes service '${SERVICE}' found. ✅"

    # You could add more sophisticated checks here, like:
    # - Checking if pods are running for the service
    # - Checking if the service has at least one endpoint

    log_info "Basic service endpoint check passed. Continuing..."
    return 0
}

update_kubernetes_ingress() {
    log_step "Updating ingress (coded)"
    log_info "Ensuring Ingress '${INGRESS_NAME}' exists in namespace '${NAMESPACE}' for service '${SERVICE}'..."

    # Determine HOSTPATH for the ingress
    local HOSTPATH
    case "$SERVICE" in
        "vault")   HOSTPATH="/ui" ;;
        "traefik") HOSTPATH="/dashboard" ;;
        *)         HOSTPATH="/" ;;
    esac

    # Render ingress manifest using heredoc, NOT inside a string!
    render_ingress_yaml() {
        cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${INGRESS_NAME}
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: traefik
    traefik.ingress.kubernetes.io/forwarded-headers-strategy: replace
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  tls:
  - hosts:
    - ${DOMAIN}
    secretName: ${SECRET_NAME}
  rules:
  - host: ${DOMAIN}
    http:
      paths:
      - path: ${HOSTPATH}
        pathType: Prefix
        backend:
          service:
            name: ${DEPLOYMENT_NAME}
            port:
              number: ${PORT}
EOF
    }

    # Check if Ingress already exists
    if ! kubectl_cmd get ingress "$INGRESS_NAME" -n "$NAMESPACE" &>/dev/null; then
        log_info "Ingress '${INGRESS_NAME}' not found. Creating it now. 🚀"
    else
        log_info "Ingress '${INGRESS_NAME}' already exists. Applying updates to annotations and TLS secret. 🔄"
    fi

    if $DRY_RUN; then
        log_info "(Dry-run) Would apply the following Ingress manifest:"
        render_ingress_yaml
        log_info "(Dry-run) Would run: kubectl apply -f -"
    else
        render_ingress_yaml | kubectl_cmd apply -f - || {
            log_error "❌ Failed to apply Ingress '${INGRESS_NAME}'."
            return 1
        }
    fi

    log_success "Ingress '${INGRESS_NAME}' configuration ensured. ✅"

    # Wait for Traefik to reload
    wait_with_dots "Giving Ingress controller time to apply new configuration (15 seconds)" 15

    return 0
}

update_kubernetes_secret() {
    log_step "Updating Kubernetes TLS Secret and Triggering Rollout"

    log_info "Creating/updating Kubernetes TLS secret '${SECRET_NAME}' in namespace '${NAMESPACE}'..."

    local SECRET_YAML=""
    # Create an array for the arguments to be passed to kubectl_cmd
    local kubectl_create_cmd_args=(
        "create" "secret" "tls" "${SECRET_NAME}"
        "--cert=${CERT_DIR}/${DOMAIN}.crt"
        "--key=${CERT_DIR}/${DOMAIN}.key"
        "-n" "${NAMESPACE}"
        "--dry-run=client" "-o" "yaml"
    )

    # Capture the clean YAML output using kubectl_cmd.
    # It's important to use kubectl_cmd here so it applies the --insecure-skip-tls-verify flag,
    # as even --dry-run=client -o yaml can involve API server validation.
    # Redirect stderr to stdout so we can capture potential errors in SECRET_YAML
    if ! SECRET_YAML=$(kubectl_cmd "${kubectl_create_cmd_args[@]}" 2>&1); then
        # Check if the error indicates a missing cert/key file which is a real problem
        if [[ "$SECRET_YAML" =~ "no such file or directory" ]]; then
            log_error "Certificate or key file not found during secret YAML generation. Path: ${CERT_DIR}/${DOMAIN}.crt / ${CERT_DIR}/${DOMAIN}.key"
            return 1
        else
            log_error "Failed to generate secret YAML. Error: ${SECRET_YAML}"
            return 1
        fi
    fi

    # Attempt to apply the secret (create or update)
    if $DRY_RUN; then
        echo "[KUBECTL] echo \"<SECRET_YAML>\" | kubectl_cmd apply -f -"
        log_info "(Dry-run) Secret YAML that would be applied (excerpt):"
        echo "${SECRET_YAML}" | head -n 10 | sed 's/^/    /'
        echo "    ..."
    else
        # Pipe the clean YAML to kubectl_cmd apply -f -.
        # kubectl_cmd will add its own [KUBECTL] prefix to its logging,
        # but that will not be part of the actual piped input to kubectl.
        echo "${SECRET_YAML}" | kubectl_cmd apply -f - || {
            log_error "Failed to apply Kubernetes secret '${SECRET_NAME}' to cluster."
            log_error "Error from kubectl: (see above for full error details, only actual kubectl output shown here)"
            return 1
        }
    fi
    log_success "Kubernetes TLS secret '${SECRET_NAME}' is applied. ✨"

    # ... rest of the function remains the same ...
    log_info "Triggering rollout restart for ${K8S_RESOURCE_TYPE} '${DEPLOYMENT_NAME}' in namespace '${NAMESPACE}'..."

    # Check if the resource exists and is of the specified type
    if ! kubectl_cmd get "${K8S_RESOURCE_TYPE}" "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" &> /dev/null; then
        log_error "${K8S_RESOURCE_TYPE^} '${DEPLOYMENT_NAME}' not found in namespace '${NAMESPACE}'. Cannot trigger rollout."
        log_error "Please ensure the resource name and type are correct. Aborting this step."
        return 1 # Fail this function if resource not found
    fi

    if [[ "$K8S_RESOURCE_TYPE" == "statefulset" ]]; then
        log_info "Ensuring StatefulSet '${DEPLOYMENT_NAME}' has 'RollingUpdate' strategy..."
        # Note: This kubectl_cmd call will also benefit from --insecure-skip-tls-verify
        if ! run_cmd "kubectl_cmd patch statefulset \"${DEPLOYMENT_NAME}\" -n \"${NAMESPACE}\" --type='json' -p='[{\"op\": \"replace\", \"path\": \"/spec/updateStrategy/type\", \"value\": \"RollingUpdate\"}]'"; then
            log_warn "Could not patch StatefulSet '${DEPLOYMENT_NAME}' to 'RollingUpdate' strategy. This might be harmless if it's already set, but check if an explicit 'OnDelete' or other strategy is preventing this."
        else
            log_success "StatefulSet '${DEPLOYMENT_NAME}' update strategy ensured to be 'RollingUpdate'."
        fi
    fi

    local SPINNER_PID=""
    if ! $DRY_RUN; then # Only start spinner if not dry-running
        start_walker_spinner & SPINNER_PID=$!
        sleep 1 # Give spinner a moment to start
    fi

    echo "🔁 Triggering rollout restart for ${K8S_RESOURCE_TYPE} '${DEPLOYMENT_NAME}'..."
    # This kubectl_cmd call will also benefit from --insecure-skip-tls-verify
    if ! run_cmd "kubectl_cmd rollout restart \"${K8S_RESOURCE_TYPE}/${DEPLOYMENT_NAME}\" -n \"${NAMESPACE}\""; then
        stop_spinner "$SPINNER_PID"
        log_error "Failed to trigger ${K8S_RESOURCE_TYPE} rollout for '${DEPLOYMENT_NAME}'. This might indicate a problem with kubectl or the resource definition."
        return 1
    fi
    log_success "${K8S_RESOURCE_TYPE^} rollout triggered for '${DEPLOYMENT_NAME}'. 🔄"

    log_info "Waiting for ${K8S_RESOURCE_TYPE} '${DEPLOYMENT_NAME}' to become ready (timeout 5m)..."
    # This kubectl_cmd call will also benefit from --insecure-skip-tls-verify
    if ! run_cmd "kubectl_cmd rollout status \"${K8S_RESOURCE_TYPE}/${DEPLOYMENT_NAME}\" -n \"${NAMESPACE}\" --timeout=5m"; then
        stop_spinner "$SPINNER_PID"
        log_error "${K8S_RESOURCE_TYPE^} '${DEPLOYMENT_NAME}' did NOT become ready within 5 minutes."
        log_error "This might indicate a problem with the ${K8S_RESOURCE_TYPE} itself, not necessarily the certs."
        log_error "Please check 'kubectl get pods -n ${NAMESPACE}' and 'kubectl logs <pod-name> -n ${NAMESPACE}' for details."
        return 1
    fi

    stop_spinner "$SPINNER_PID"
    log_success "${K8S_RESOURCE_TYPE^} '${DEPLOYMENT_NAME}' rollout complete ✅"
    wait_with_dots "Letting Kubernetes and Ingress settle (30s)" 30
    return 0
}

display_manual_windows_trust_instructions() {
    log_step "Display manual cert instructions (coded)"
    echo "⚠️ Manually install the root CA on Windows if not done already."

    log_info "Generating command for manual Windows CA trust..."
    # Ensure wslpath is available
    if ! command -v wslpath >/dev/null 2>&1; then
        log_error "Missing 'wslpath' tool. Cannot generate manual Windows trust command."
        log_error "Please ensure WSL is correctly installed and integrated with Windows."
        exit 1
    fi

    # Get the WSL path to the mkcert root CA
    local CAROOT="$(mkcert -CAROOT)"
    local CA_PEM="${CAROOT}/rootCA.pem"

    if [[ ! -f "${CA_PEM}" ]]; then
        log_error "mkcert CA missing at ${CA_PEM}. Cannot generate manual Windows trust command."
        log_error "Please ensure mkcert has successfully installed its CA."
        exit 1
    fi

    # Convert WSL path to Windows path for certutil, ensuring no hidden newlines
    local WIN_CA_PATH="$(wslpath -w "${CA_PEM}" | tr -d '\r\n')"

    echo ""
    echo "================================================================================="
    echo "================================================================================="
    echo " 🚨 IMPORTANT MANUAL STEP: TRUSTING THE mkcert CA & UPDATING HOSTS IN WINDOWS 🚨"
    echo "================================================================================="
    echo ""
    echo " Your Windows browser (Chrome, Edge, Firefox, etc.) needs to trust the"
    echo " mkcert Root CA that was just generated for HTTPS to work without warnings."
    echo ""
    echo " You also need to add an entry to your Windows hosts file so your browser"
    echo " can resolve '${DOMAIN}' to your local Kubernetes cluster."
    echo ""
    echo " This step requires **Administrator privileges** in Windows."
    echo ""
    echo " ➡️  PLEASE COPY THE FOLLOWING COMMANDS AND RUN THEM IN A NEW WINDOW:"
    echo "    1. Search for 'PowerShell' in your Windows Start Menu."
    echo "    2. Right-click on 'Windows PowerShell' (or 'PowerShell') and select"
    echo "      'Run as administrator'."
    echo "    3. Paste the commands below into the Administrator PowerShell window and press Enter."
    echo ""
    echo "    ------------------------------------------------------------------------"
    printf '    # Command to install mkcert Root CA:\n'
    printf '    certutil -addstore -f "ROOT" "%s"\n' "${WIN_CA_PATH}"
    echo ""
    printf '    # Command to open hosts file for editing (add "127.0.0.1 %s"):\n' "${DOMAIN}"
    echo '    notepad.exe $env:SystemRoot\System32\drivers\etc\hosts'
    echo "    ------------------------------------------------------------------------"
    echo ""
    echo " ➡️  What to look for:"
    echo "    - For 'certutil': A Windows User Account Control (UAC) prompt: **CLICK 'YES'**"
    echo "      You should see: 'Certificate is added to store.'"
    echo "    - For 'notepad.exe': Your hosts file will open. Add the line '127.0.0.1 ${DOMAIN}'"
    echo "      (without quotes) at the end, save the file, and close Notepad."
    echo "      Example: 127.0.0.1 vault.helix"
    echo ""
    echo " Once you have successfully completed both actions, press Enter here to continue the script."
    echo "================================================================================="
    echo "================================================================================="
    echo ""
    # Only prompt if not in dry-run mode
    if ! $DRY_RUN; then
        read -rp "Press Enter to confirm you have completed the Windows CA trust and hosts file steps (or Ctrl+C to abort)..."
        log_success "Manual Windows CA trust and hosts file steps confirmed. ✅"
    else
        log_info "(Dry-run) Manual Windows CA trust and hosts file steps would be prompted here."
    fi
    echo ""
}

# --- Placeholder Functions (If you decide not to use cert-manager for this script) ---
create_cert_manager_certificate() {
    log_step "Creating cert-manager Certificate resource (SKIPPING - using mkcert directly)"
    log_info "This script is configured to use mkcert for direct TLS secret creation."
    log_info "If you wish to use cert-manager, this function would contain the 'kubectl apply' for your Certificate resource."
    return 0 # Always succeed as it's a skipped step
}

trust_cert_manager_ca() {
    log_step "Trusting cert-manager CA (SKIPPING - using mkcert directly)"
    log_info "This script is configured to use mkcert's generated CA, not a cert-manager CA for system trust."
    log_info "If you were using cert-manager with a custom CA, this function would handle its trust."
    return 0 # Always succeed as it's a skipped step
}

verify_tls_connectivity() {
    log_step "Verifying TLS connectivity (coded)"

    local domain_to_check="${DOMAIN}"
    local OPEN_URL="https://${DOMAIN}${HOSTPATH}" # Construct full URL
    log_debug "OPEN_URL for connectivity check: ${OPEN_URL}"

    log_info "⚡ Verifying basic TLS reachability for ${OPEN_URL} using ping + curl..."

    if $DRY_RUN; then
        log_info "(Dry-run) Would perform TLS ping + curl check for ${OPEN_URL}."
        echo "[DRY-RUN] Ping: ping -c 1 -W 2 ${domain_to_check}"
        echo "[DRY-RUN] Curl: curl --max-time 15 --silent --fail ${OPEN_URL}"
        return 0
    fi

    # Step 1: DNS check (ping)
    if ! ping -c 1 -W 2 "${domain_to_check}" >/dev/null 2>&1; then
        log_error "❌ Ping to '${domain_to_check}' failed. Check /etc/hosts in Windows/WSL or DNS setup."
        return 1
    fi
    log_success "✅ Ping to '${domain_to_check}' succeeded."

    # Step 2: Curl HTTPS check with validation
    log_info "Attempting curl to ${OPEN_URL}..."
    # The --cacert option tells curl to trust your custom CA (mkcert's rootCA.pem).
    # This is crucial for local testing where your browser trusts it, but curl itself needs explicit instruction.
    # The path to ca.crt within CERT_DIR needs to be correct.
    local LOCAL_CA_PATH="${CERT_DIR}/ca.crt"
    if [[ ! -f "$LOCAL_CA_PATH" ]]; then
        log_error "Local CA certificate not found at '${LOCAL_CA_PATH}'. Cannot perform full TLS verification with curl."
        log_error "Make sure 'setup_wsl_certs' ran successfully."
        # Attempt curl without CA validation, but warn
        log_warn "Proceeding with curl --insecure (no CA validation) due to missing local CA."
        if ! curl --max-time 15 --silent --fail --insecure "${OPEN_URL}"; then
            log_error "❌ Curl to '${OPEN_URL}' failed (without CA validation). Check service and ingress configuration."
            return 1
        fi
    else
        if ! curl --max-time 15 --silent --fail --cacert "${LOCAL_CA_PATH}" "${OPEN_URL}"; then
            log_error "❌ Curl to '${OPEN_URL}' failed (with CA validation). This might mean the certificate setup is incorrect or the service is not ready."
            return 1
        fi
    fi

    log_success "✅ Curl to '${OPEN_URL}' succeeded. TLS connection appears to be working correctly. 🎉"
    return 0
}

# --- Main Script Execution ---

main() {
    log_step "Starting TLS Certificate Management and Kubernetes Deployment Script"

    # 1. Discover Cluster and Namespace
    # This is now responsible for setting the kubectl context AND applying RBAC.
    if ! discover_cluster_and_namespace; then
        log_error "Initial setup failed: cluster or namespace discovery, or RBAC application failed. Exiting."
        exit 1
    fi

    # 2. Fix Kubeconfig Server Address
    # Now that CLUSTER_NAME is set, fix_k3d_kubeconfig_server_address can use it.
    fix_k3d_kubeconfig_server_address
    k3d kubeconfig get helix > ~/.kube/config
    kubectl get nodes
    kubectl auth can-i get nodes --as=system:anonymous

    # 3. Discover Service Details (after cluster/namespace are known)
    if ! discover_service_details; then
        log_error "Failed to discover service details. Exiting."
        exit 1
    fi

    # 4. Set up WSL Certs (mkcert)
    if ! setup_wsl_certs; then
        log_error "Failed to set up WSL certificates. Exiting."
        exit 1
    fi

    # 5. Update Kubernetes TLS Secret and Trigger Rollout
    # RBAC permissions should already be in place due to `discover_cluster_and_namespace`
    if ! update_kubernetes_secret; then
        log_error "Failed to update Kubernetes TLS secret or trigger rollout. Exiting."
        exit 1
    fi

    # 6. Update Kubernetes Ingress (after secret is ready)
    if ! update_kubernetes_ingress; then
        log_error "Failed to update Kubernetes Ingress. Exiting."
        exit 1
    fi

    # 7. Check Service Endpoints
    if ! check_service_endpoints; then
        log_error "Service endpoint check failed. Exiting."
        exit 1
    fi

    # 8. Verify TLS Connectivity
    if ! verify_tls_connectivity; then
        log_error "TLS connectivity verification failed. Exiting."
        exit 1
    fi

    # 9. Display Manual Windows Trust Instructions (if applicable)
    display_manual_windows_trust_instructions

    log_success "Script finished successfully for service '${SERVICE}' on domain 'https://${DOMAIN}'. 🎉"
    log_info "You should now be able to access your service via https://${DOMAIN}${HOSTPATH} from your Windows browser."
}

# Run the main function
main "$@"