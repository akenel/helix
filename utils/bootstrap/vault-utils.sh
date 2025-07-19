#!/usr/bin/env bash
# 🧭 vault-utils.sh — Utility functions for interacting with HashiCorp Vault
# This script defines functions to be sourced by other deployment scripts.

# Ensure script exits on error, unset variables, and pipe failures
set -euo pipefail

# Get the directory where this script is located
# SCRIPT_DIR needs to be global here for sourcing other utilities if run standalone
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HELIX_BOOTSTRAP_DIR="$SCRIPT_DIR"
# Source logging utilities (expected to be present from 00_run_all_steps.sh)
# Fallback if not sourced (for standalone testing or if parent doesn't source spinner_utils.sh first)
if ! command -v log_info >/dev/null 2>&1; then
    echo "WARNING: Logging functions (log_info, etc.) not found. Using basic echo." >&2
    log_info() { echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S %Z') $1"; }
    log_success() { echo "[SUCCESS] $(date +'%Y-%m-%d %H:%M:%S %Z') $1"; }
    log_warn() { echo "[WARN] $(date +'%Y-%m-%d %H:%M:%S %Z') $1" >&2; }
    log_error() { echo "[ERROR] $(date +'%Y-%m-%d %H:%M:%S %Z') $1" >&2; }
fi

# Define standard paths for Vault secrets files
# These paths must match where 03-vault-bootstrap-unseal.sh saves them.
# HELIX_BOOTSTRAP_DIR is expected to be exported by 00_run_all_steps.sh
# Define standard paths for Vault secrets files
VAULT_CONFIG_DIR="$HOME/helix_v3/bootstrap/addon-configs/vault"
VAULT_ENV_FILE="${VAULT_CONFIG_DIR}/vault.env"
VAULT_ROOT_TOKEN_FILE="${VAULT_CONFIG_DIR}/.vault_root_token"
echo "🔚 Inside VAULT_ROOT_TOKEN_FILE="${VAULT_CONFIG_DIR}/.vault_root_token""

# ──────────────────────────────────────────────────────────────────────────────
# Function: load_vault_token
# Purpose: Loads Vault environment variables and tokens from saved files.
# Exports: VAULT_ADDR, VAULT_TOKEN (deployment), VAULT_NAMESPACE, VAULT_RELEASE,
#          VAULT_ROOT_TOKEN, VAULT_POD_NAME
# Returns: 0 on success, 1 on failure
# ──────────────────────────────────────────────────────────────────────────────
load_vault_token() {
    echo "(🔚) Attempting to load Vault environment and tokens..."
    log_info "(🔚) Attempting to load Vault environment and tokens..."

    if [[ ! -f "$VAULT_ENV_FILE" || ! -f "$VAULT_ROOT_TOKEN_FILE" ]]; then
        auto_generate_vault_env_and_token || return 1
    fi

    set -a
    source "$VAULT_ENV_FILE"
    set +a

    export VAULT_ROOT_TOKEN=$(cat "$VAULT_ROOT_TOKEN_FILE")

    # Dynamically find the Vault pod name if not already set
        if [[ -z "${VAULT_POD_NAME:-}" ]]; then
        VAULT_POD_NAME=$(kubectl get pods -n "$VAULT_NAMESPACE" \
            -l "app.kubernetes.io/instance=$VAULT_RELEASE,component=server" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        export VAULT_POD_NAME
        fi

    
    if [[ -z "$VAULT_POD_NAME" ]]; then
        log_error "Vault pod not found in namespace '${VAULT_NAMESPACE}' with release '${VAULT_RELEASE}'. Is Vault running?"
        return 1
    fi

    log_success "Vault environment and tokens loaded."
    log_info "  VAULT_ADDR: ${VAULT_ADDR}"
    log_info "  VAULT_NAMESPACE: ${VAULT_NAMESPACE}"
    log_info "  VAULT_RELEASE: ${VAULT_RELEASE}"
    log_info "  VAULT_POD_NAME: ${VAULT_POD_NAME}"
    return 0
}

# ──────────────────────────────────────────────────────────────────────────────
# Function: enable_kv_if_missing
# Purpose: Enables the 'secret/' KV engine in Vault if it's not already enabled.
# Requires: VAULT_NAMESPACE, VAULT_POD_NAME, VAULT_ADDR, VAULT_ROOT_TOKEN to be exported.
# Returns: 0 on success, 1 on failure
# ──────────────────────────────────────────────────────────────────────────────
enable_kv_if_missing() {
    log_info "🔐 Checking 'secret/' KV engine in Vault..."
    # Execute vault secrets list inside the pod
    if ! kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD_NAME" -- \
        sh -c "VAULT_ADDR='$VAULT_ADDR' VAULT_TOKEN='$VAULT_ROOT_TOKEN' \
               vault secrets list -format=json" | jq -e '."secret/"' &>/dev/null; then
        log_warn "🛠️ Enabling 'secret/' KV engine..."
        # Execute vault secrets enable inside the pod
        if ! kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD_NAME" -- \
            sh -c "VAULT_ADDR='$VAULT_ADDR' VAULT_TOKEN='$VAULT_ROOT_TOKEN' \
                   vault secrets enable -path=secret kv"; then
            log_error "Failed to enable KV engine."
            return 1
        fi
        log_success "'secret/' KV engine enabled."
    else
        log_info "'secret/' KV already enabled."
    fi
    return 0
}

# ──────────────────────────────────────────────────────────────────────────────
# Function: store_secret
# Purpose: Stores a key-value secret in Vault.
# Args:    $1 = Vault path (e.g., "secret/my-app/credentials")
#          $@ = Key-value pairs (e.g., "username=myuser" "password=mypass")
# Requires: VAULT_NAMESPACE, VAULT_POD_NAME, VAULT_ADDR, VAULT_ROOT_TOKEN to be exported.
# Returns: 0 on success, 1 on failure
# ──────────────────────────────────────────────────────────────────────────────
store_secret() {
    local path="$1"; shift
    local args=("$@")

    log_info "💾 Writing secret to Vault at '$path'..."
    # Construct the vault put command safely, quoting each argument
    local vault_put_cmd="vault kv put ${path}"
    for arg in "${args[@]}"; do
        vault_put_cmd+=" \"${arg}\"" # Quote arguments to handle spaces/special chars
    done

    # Execute vault kv put inside the pod
    if ! kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD_NAME" -- /bin/sh -c "
        VAULT_ADDR='$VAULT_ADDR' VAULT_TOKEN='$VAULT_ROOT_TOKEN' \
        ${vault_put_cmd}
    "; then
        log_error "Failed to store secret at $path"
        return 1
    fi
    log_success "Secrets stored at $path 🔒"
    return 0
}
# Auto-generate Vault env/token files if missing (fallback bootstrap)
auto_generate_vault_env_and_token() {
    log_warn "Vault environment or token files missing. Attempting to auto-generate..."

    mkdir -p "$VAULT_CONFIG_DIR"

    if [[ ! -f "$VAULT_ENV_FILE" ]]; then
        log_info "Creating default vault.env..."
        cat <<EOF > "$VAULT_ENV_FILE"
VAULT_ADDR=http://127.0.0.1:8200
VAULT_NAMESPACE=vault
VAULT_RELEASE=vault-helix
# VAULT_TOKEN will be loaded below or retrieved dynamically
EOF
        log_success "Generated default vault.env at $VAULT_ENV_FILE"
    fi

    # Attempt to get the Vault pod name (if not set)
    VAULT_NAMESPACE=${VAULT_NAMESPACE:-vault}
    VAULT_RELEASE=${VAULT_RELEASE:-vault-helix}
    VAULT_POD_NAME=$(kubectl get pods -n "$VAULT_NAMESPACE" -l "app.kubernetes.io/instance=$VAULT_RELEASE,component=server" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -z "$VAULT_POD_NAME" ]]; then
        log_error "Could not auto-detect Vault pod. Is Vault deployed?"
        return 1
    fi

    # Try to extract root token from pod logs (only if token file is missing)
    if [[ ! -f "$VAULT_ROOT_TOKEN_FILE" ]]; then
        log_info "Attempting to extract Vault root token from pod logs..."

        VAULT_ROOT_TOKEN=$(kubectl logs -n "$VAULT_NAMESPACE" "$VAULT_POD_NAME" 2>/dev/null | grep 'Root Token:' | awk '{print $NF}')
        if [[ -z "$VAULT_ROOT_TOKEN" ]]; then
            log_error "Failed to extract root token from logs. You may need to manually unseal Vault."
            return 1
        fi

        echo "$VAULT_ROOT_TOKEN" > "$VAULT_ROOT_TOKEN_FILE"
        log_success "Vault root token saved to $VAULT_ROOT_TOKEN_FILE"
    fi

    return 0
}
