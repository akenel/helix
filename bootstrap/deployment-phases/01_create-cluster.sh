#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR
# 🧠 Helix Whip — bootstrap/deployment-phases/00_run_all_steps.sh

# ─── Shell Armor ───────────────────────────────────────────────
set -euo pipefail
shopt -s failglob
clear

VERSION="v0.0.3-beta"
echo "🔐 Helix Deployment Bootstrap — ${VERSION}"

# ─── Resolve Paths ─────────────────────────────────────────────
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
DEPLOY_PHASES_DIR="${SCRIPT_DIR}"

# Go two levels up to get the project root (helix/)
HELIX_ROOT_DIR="$(realpath "$SCRIPT_DIR/../..")"
export HELIX_ROOT_DIR

# ─── Load Env Loader ───────────────────────────────────────────
ENV_LOADER_PATH="${HELIX_ROOT_DIR}/bootstrap_env_loader.sh"

if [[ ! -f "$ENV_LOADER_PATH" ]]; then
  echo "❌ ERROR: bootstrap_env_loader.sh not found at: $ENV_LOADER_PATH"
  exit 1
fi
source "$ENV_LOADER_PATH"

# ─── Validation ────────────────────────────────────────────────
UTILS_DIR="${SCRIPT_DIR}/utils"
if [[ ! -d "$UTILS_DIR" ]]; then
  echo "❌ ERROR: utils directory missing at: $UTILS_DIR"
  exit 1
fi
echo "🐧 UTILS_DIR: $UTILS_DIR"
# ─── Load Utilities ────────────────────────────────────────────
source "${UTILS_DIR}/core/spinner_utils.sh"
source "${UTILS_DIR}/core/print_helix_banner.sh"
source "${UTILS_DIR}/core/deploy-footer.sh"
source "${UTILS_DIR}/bootstrap/cluster_info.sh"

echo "🚀 RUNNING Bootstrap Utilities via: ${UTILS_DIR}/cluster_info.sh"
# ── Pre-Checks ───────────────────────────────────────────────────────────────
check_dependencies() {
    if ! command -v mkcert &> /dev/null; then
        echo "❌ mkcert is not installed. Please install it: https://github.com/FiloSottile/mkcert#installation"
        return 1
    fi

    if ! command -v yq &> /dev/null; then
        echo "❌ 'yq' is required but not found. Install it via 'brew install yq' or 'snap install yq'"
        return 1
    fi
}
# ── Cluster Management ────────────────────────────────────────────────────────
create_k3d_cluster() {
  local cluster_name=$1
  local registry_name=$2
  local tls_domains=$3
  local MAX_RETRIES=10
  local RETRY_DELAY=5

  # Check if the cluster exists
  if k3d cluster list | grep -q "$cluster_name"; then
    echo "⚠️  Cluster '$cluster_name' already exists."
    read -p "❓ Do you want to delete and recreate it? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      echo "🗑️  Deleting cluster '$cluster_name'..."

      for attempt in $(seq 1 $MAX_RETRIES); do
        echo "🔄 Attempt $attempt to delete cluster..."
        k3d cluster delete "$cluster_name" || true

        sleep "$RETRY_DELAY"

        # Check if any k3d-* containers remain
        if docker ps -a --format '{{.Names}}' | grep -q "k3d-${cluster_name}-server"; then
          echo "⏳ Waiting: server container still present..."

          # Force kill and remove
          docker rm -f "k3d-${cluster_name}-server-0" 2>/dev/null || true
        fi

        # Check if volume is still mounted
        if docker volume ls --format '{{.Name}}' | grep -q "k3d-${cluster_name}-images"; then
          echo "💣 Removing leftover volume..."
          docker volume rm "k3d-${cluster_name}-images" 2>/dev/null || true
        fi

        # Check again if cluster is truly gone
        if ! k3d cluster list | grep -q "$cluster_name" && \
           ! docker ps -a | grep -q "k3d-${cluster_name}-server"; then
          echo "✅ Cluster '$cluster_name' deleted successfully."
          break
        fi

        if [[ $attempt -eq $MAX_RETRIES ]]; then
          echo -e "${RED}❌ Failed to fully delete cluster after $MAX_RETRIES attempts.${NC}"
          return 1
        fi
      done
    else
      echo "🚪 Exiting to main menu. Cluster was not deleted."
      exit 0
    fi
  else
    echo "🌱 No existing cluster named '$cluster_name' found. Proceeding to create it."
  fi

  # Create registry if needed
  if ! k3d registry list | grep -q "$registry_name"; then
    echo "📦 Creating local registry: $registry_name"
    k3d registry create "$registry_name"
  else
    echo "📦 Registry '$registry_name' already exists."
  fi

  # Mount Keycloak themes and realms if available
  local KEYCLOAK_THEMES_PATH="$(realpath "bootstrap/addon-configs/keycloak/themes")"
  local KEYCLOAK_REALMS_PATH="$(realpath "bootstrap/addon-configs/keycloak/realms")"
  local EXTRA_MOUNTS=""

  [[ -d "$KEYCLOAK_THEMES_PATH" ]] && EXTRA_MOUNTS+=" --volume $KEYCLOAK_THEMES_PATH:/helix-assets" || echo "⚠️ Skipping theme mount"
  [[ -d "$KEYCLOAK_REALMS_PATH" ]] && EXTRA_MOUNTS+=" --volume $KEYCLOAK_REALMS_PATH:/keycloak-configs" || echo "⚠️ Skipping realm mount"

  # Create the new cluster
  echo "🚀 Creating k3d cluster '$cluster_name' with TLS SANs trusted by mkcert CA..."
  k3d cluster create "$cluster_name" \
    --api-port 6550 \
    --port 80:80@loadbalancer \
    --port 443:443@loadbalancer \
    --port 9000:9000@loadbalancer \
    --registry-use "$registry_name" \
    --servers 1 \
    --agents 0 \
    --env K3S_KUBECONFIG_MODE=644@server:0 \
    --env K3S_TLS_SAN="$tls_domains"@server:0 \
    --k3s-arg "--tls-san=127.0.0.1"@server:0 \
    --kubeconfig-update-default=false \
    --kubeconfig-switch-context=false \
    $EXTRA_MOUNTS

  echo "✅ Cluster '$cluster_name' successfully created."
}

# ── Cluster Verification ───────────────────────────────────────────────────────
verify_cluster() {
    local cluster_name=$1
    local kubeconfig_file=$2

    echo "⏳ Verifying Kubernetes API server connectivity and TLS..."

    # Loop for API health check
    for i in {1..20}; do
        echo "🔄 Attempt $i/20: Checking API readiness..."
        sleep 5

        API_HEALTH_CHECK=$(KUBECONFIG="$kubeconfig_file" kubectl get --raw=/healthz 2>&1 || true)
        if echo "$API_HEALTH_CHECK" | grep -q "ok"; then
            echo "✅ API is healthy."
            break
        else
            echo "❌ API not yet ready."
            echo "    Health check: $API_HEALTH_CHECK"
        fi

        if [[ "$i" -eq 20 ]]; then
            echo "‼️ Failed to get healthy API after multiple attempts."
            echo "‼️ Check K3s server logs:"
            k3d node logs "$cluster_name-server-0"
            exit 1
        fi
    done

    echo "🔍 Validating TLS certificate of Kubernetes API server..."
    echo
    local api_server_url host_and_port cert_info
    api_server_url=$(KUBECONFIG="$kubeconfig_file" kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
            
            echo "🔍 api_server_url $api_server_url"
    host_and_port=$(echo "$api_server_url" | sed 's|https://||')
    echo "🔍 Connecting to API server host_and_port at: $host_and_port"
    # Now run the openssl s_client command and capture full output
    cert_info=$(timeout 10 openssl s_client -connect "$host_and_port" -servername "$host_and_port" -showcerts </dev/null 2>&1)

    if [[ $? -ne 0 || -z "$cert_info" ]]; then
        echo "❌ Failed to retrieve TLS certificate from API server!"
        echo "    OpenSSL output:"
        echo "$cert_info"
        echo "    Check if the cluster API is still reachable and not using a non-trusted cert."
        k3d node logs "$cluster_name-server-0"
        exit 1
    fi

    # Extract certificate and parse it with openssl x509
    local san_output
    san_output=$(echo "$cert_info" | openssl x509 -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name")

    if [[ -n "$san_output" ]]; then
        echo
        echo "$san_output"
        echo
        echo "✅ Kubernetes API server TLS certificate validation successful."
    else
        echo "⚠️ Certificate retrieved, but SANs could not be parsed. Displaying partial OpenSSL output for diagnostics:"
        echo "$cert_info" | head -n 20
        exit 1
    fi

    echo "✅ Kubernetes API server connectivity and TLS verification complete."
}
# ── Cert-Manager and CA Issuer Setup ───────────────────────────────────────────
install_cert_manager() {
    # Install Cert-Manager
    REPO_NAME="jetstack"
    REPO_URL="https://charts.jetstack.io"

    if ! helm repo list | grep -q "$REPO_NAME"; then
    echo "📦 Adding Helm repository: $REPO_NAME"
    helm repo add "$REPO_NAME" "$REPO_URL"
    else
    echo "📦 Helm repository '$REPO_NAME' already exists. Skipping 'helm repo add'."
    fi
    helm repo update
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.14.0 \
        --set installCRDs=true \
        --wait

    echo "⏳ Waiting for cert-manager pods to be ready..."
    kubectl rollout status deployment/cert-manager -n cert-manager
    kubectl rollout status deployment/cert-manager-webhook -n cert-manager
    kubectl rollout status deployment/cert-manager-cainjector -n cert-manager
}
configure_ca_issuer() {
    local mkcert_root_ca_pem=$1
    local mkcert_root_ca_key=$2
    # Create a Kubernetes Secret for the mkcert root CA and key
    local mkcert_root_ca_cert_base64
    mkcert_root_ca_cert_base64=$(base64 -w 0 "$mkcert_root_ca_pem")
    local mkcert_root_ca_key_base64
    mkcert_root_ca_key_base64=$(base64 -w 0 "$mkcert_root_ca_key")

    cat <<EOF > "./test_mkcert-ca-secret.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: mkcert-root-ca-secret
  namespace: cert-manager
type: kubernetes.io/tls
data:
  tls.crt: $mkcert_root_ca_cert_base64
  tls.key: $mkcert_root_ca_key_base64
EOF
    kubectl apply -f "./test_mkcert-ca-secret.yaml"
    rm "./test_mkcert-ca-secret.yaml"

    # Apply the ClusterIssuer configuration
    cat <<EOF > "./test_mkcert-ca-issuer.yaml"
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: mkcert-ca-issuer
spec:
  ca:
    secretName: mkcert-root-ca-secret
EOF
    kubectl apply -f "./test_mkcert-ca-issuer.yaml"
    rm "./test_mkcert-ca-issuer.yaml"
}
generate_kubeconfig_from_k3d() {
    local cluster_name=$1
    local final_kubeconfig_path="${2:-$DEFAULT_KUBECONFIG_PATH}"

    echo "🔧 Writing kubeconfig for new cluster '$cluster_name' to: $final_kubeconfig_path"

    mkdir -p "$(dirname "$final_kubeconfig_path")"
    k3d kubeconfig get "$cluster_name" > "$final_kubeconfig_path"

    chmod 600 "$final_kubeconfig_path"
    export KUBECONFIG="$final_kubeconfig_path"
    echo "🔧 Final kube configured path $KUBECONFIG"

    local context_name
    context_name=$(kubectl config --kubeconfig="$final_kubeconfig_path" current-context 2>/dev/null || true)
    echo "🔧 Setting: kubectl config use-context $context_name"
    if [[ -n "$context_name" ]]; then
        kubectl config use-context "$context_name"
    else
        echo "⚠️ Could not detect current context in kubeconfig. Continuing..."
    fi
}
#
install_cert_manager_csi_driver() {
    echo "📦 Installing cert-manager CSI driver..."

    helm repo add cert-manager-csi https://charts.jetstack.io
    helm repo update

    helm install cert-manager-csi cert-manager-csi/cert-manager-csi-driver \
        --namespace cert-manager \
        --wait
    echo "📦 Check cert-manager CSI driver is running now..."

    kubectl get daemonset cert-manager-csi-driver -n cert-manager
}
test_cert_manager_csi_driver() {
    local kubeconfig_file=$1
    local kubeconfig_dir="$HOME/.helix"
    local test_yaml="$kubeconfig_dir/test-mkcert-csi-pod.yaml"

    echo "📦 Testing cert-manager CSI driver with example pod..."

    cat <<EOF > "$test_yaml"
apiVersion: v1
kind: Pod
metadata:
  name: cert-test
  namespace: default
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: tls
      mountPath: /tls
      readOnly: true
  volumes:
  - name: tls
    csi:
      driver: csi.cert-manager.io
      readOnly: true
      volumeAttributes:
        csi.cert-manager.io/issuer-name: mkcert-ca-issuer
        csi.cert-manager.io/issuer-kind: ClusterIssuer
        csi.cert-manager.io/dns-names: cert-test.default.svc
EOF
    echo "📜 Applying test pod manifest..."
    kubectl apply -f "$test_yaml" --kubeconfig "$kubeconfig_file" >/dev/null
    rm "$test_yaml"
    echo -n "⏳ Waiting for cert-test pod to be ready "
    local spin='|/-\'
    local i=0
    # Background spinner
    {
        while true; do
            i=$(( (i+1) % 4 ))
            printf "\b${spin:$i:1}"
            sleep 0.1
        done
    } &
    local spinner_pid=$!
    # Wait for pod to report Ready
    kubectl wait pod cert-test -n default \
        --for=condition=Ready \
        --timeout=90s \
        --kubeconfig "$kubeconfig_file" >/dev/null 2>&1
    local result=$?
    kill "$spinner_pid" >/dev/null 2>&1
    wait "$spinner_pid" 2>/dev/null || true
    if [[ "$result" -ne 0 ]]; then
        echo -e "\b❌"
        echo "❌ cert-test pod did not report Ready in time."
        kubectl describe pod cert-test --kubeconfig "$kubeconfig_file"
        exit 1
    fi
    echo -e "\b✅"
    echo "🔍 Verifying mounted certificate..."
    if ! kubectl exec cert-test --kubeconfig "$kubeconfig_file" -- ls /tls >/dev/null 2>&1; then
        echo "❌ No certificate mounted at /tls!"
        kubectl logs cert-test --kubeconfig "$kubeconfig_file" || true
        exit 1
    fi
    echo "📄 Certificate SAN (Subject Alternative Name):"
    kubectl exec cert-test --kubeconfig "$kubeconfig_file" -- cat /tls/tls.crt \
        | openssl x509 -noout -text 2>/dev/null \
        | grep -A1 "Subject Alternative Name"
    echo "✅ CSI driver issued and mounted certificate successfully!"
    echo "🧹 Cleaning up test pod..."
    kubectl delete pod cert-test --kubeconfig "$kubeconfig_file" --grace-period=0 --force >/dev/null 2>&1
    echo "✅ Cleanup complete."
    # 🎉 THE GRAND ASCII MOMENT
    print_helix_banner "Tested Sucsessfully : test v1.0.1" "Cluster Online • TLS Verified"
}
banner_spinner() {
    local message="$1"
    local command="$2"
    local spinner=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local delay=0.1
    local pid spin_index=0

    # Start command in background
    eval "$command" &
    pid=$!

    # Trap cleanup
    trap "kill $pid 2>/dev/null" EXIT

    # Display spinner while command runs
    tput civis  # Hide cursor
    echo -ne " $message "
    while kill -0 $pid 2>/dev/null; do
        printf "\r %s %s" "${spinner[spin_index]}" "$message"
        spin_index=$(( (spin_index + 1) % ${#spinner[@]} ))
        sleep "$delay"
    done
    wait $pid
    exit_code=$?
    tput cnorm  # Restore cursor
    trap - EXIT

    if [[ $exit_code -eq 0 ]]; then
        printf "\r✅ %s\n" "$message"
    else
        printf "\r❌ %s\n" "$message"
        return $exit_code
    fi
}
show_cluster_info() {
    local cluster_name=$1
    local registry_name=$2
    local kubeconfig_file=$3

    echo "🎯 Cluster:             $cluster_name"
    echo "📦 Registry:            $registry_name"
    echo "📜 Kubeconfig:          $kubeconfig_file"
    echo "🧪 TLS for API:         K3s self-signed (trusted by mkcert CA in kubeconfig)"
    echo "📡 API:                 https://127.0.0.1:6550"
    echo "🔒 Cert-Manager:        Installed and configured with mkcert-ca-issuer"
    echo ""

    kubectl config get-contexts
    kubectl get nodes
    kubectl get ns
    kubectl get pods -n cert-manager
    kubectl get clusterissuers
}
# ── Main Script ───────────────────────────────────────────────────────────────
main() {
    local cluster_name="${1:-helix}"
    local registry_name="${2:-helix-registry}"
    local tls_domains="127.0.0.1 localhost keycloak.helix vault.helix portainer.helix traefik.helix adminer.helix"
    local kubeconfig_dir="$HOME/.helix"
    local kubeconfig_file="$kubeconfig_dir/kubeconfig.yaml"
    local mkcert_root_ca_dir="$(mkcert -CAROOT)"
    local mkcert_root_ca_pem="$mkcert_root_ca_dir/rootCA.pem"
    local mkcert_root_ca_key="$mkcert_root_ca_dir/rootCA-key.pem"
    # Pre-checks
    check_dependencies || exit 1
    mkcert -install 2>/dev/null
    mkcert --CAROOT
    # Cluster management
    create_k3d_cluster "$cluster_name" "$registry_name" "$tls_domains"
    # Kubeconfig management
    generate_kubeconfig_from_k3d "$cluster_name" "$kubeconfig_file"
    # Verify the cluster
    verify_cluster "$cluster_name" "$kubeconfig_file"
    # Cert-Manager and CSI setup
    install_cert_manager
    install_cert_manager_csi_driver
    configure_ca_issuer "$mkcert_root_ca_pem" "$mkcert_root_ca_key"
    test_cert_manager_csi_driver "$kubeconfig_file"
    configure_ca_issuer "$mkcert_root_ca_pem" "$mkcert_root_ca_key"
    # Verification and summary
    show_cluster_info "$cluster_name" "$registry_name" "$kubeconfig_file"
}
main "$@"