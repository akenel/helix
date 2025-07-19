#!/usr/bin/env bash
# 🧭 cluster_info.sh — Displays current Kubernetes cluster context information.
# This script is intended to be sourced by other scripts.

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logging utilities if they are not already available
# This ensures that log_info, log_error, etc. are available for this script.
# We'll assume spinner_utils.sh is the source for these.
if ! command -v log_info >/dev/null 2>&1; then
    # Fallback if log_info is not sourced from parent (e.g., if this script is run standalone)
    echo "WARNING: Logging functions (log_info, etc.) not found. Using basic echo." >&2
    log_info() { echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S %Z') $1"; }
    log_success() { echo "[SUCCESS] $(date +'%Y-%m-%d %H:%M:%S %Z') $1"; }
    log_warn() { echo "[WARN] $(date +'%Y-%m-%d %H:%M:%S %Z') $1" >&2; }
    log_error() { echo "[ERROR] $(date +'%Y-%m-%d %H:%M:%S %Z') $1" >&2; }
fi

# Source the deploy-footer.sh using its absolute path relative to this script's location
source "${SCRIPT_DIR}/deploy-footer.sh"

# Function to display initial deployment summary and environment info
# 🧬 Cluster Info Module — Safe & Dynamic 🛰️

cluster_info() {
  # Fall back to defaults if variables are unset (Option 1)
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
  echo "🗓   $(date)"
  echo "📍 ${CITY}, ${REGION}, ${COUNTRY} — 🌤  ${TEMP}°C, Wind ${WIND} km/h"
  echo "🐳 Docker: ${DOCKER} • 🐧 Linux: ${LINUX}"
  echo "---------------------------------------------"
  echo ""
  echo "🎬 Deployment Summary:"
  echo "📦 Services:"
  echo "    🟢 Vault     ⏳"
  echo "    🟢 Portainer ⏳"
  echo "    🟢 Postgres  ⏳"
  echo "    🟢 Keycloak  ⏳"
  echo "    🟢 Adminer   ⏳"
  echo "    🟢 Kafka     ⏳"
  echo "    🟢 Kong      ⏳"
  echo ""
  echo "🔐 TLS Chain:"
  echo "    🔐 mkcert CA         ⏳"
  echo "    🔐 ClusterIssuer     ⏳"
  echo "    🔐 Kubeconfig Patched  ⏳"
  echo ""
  echo "📊 Secrets:"
  echo "    🔑 Vault KV          ⏳"
  echo "    🔑 App Keys Injected ⏳"
  echo ""
}

