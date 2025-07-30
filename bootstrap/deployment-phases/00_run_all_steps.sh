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

# Go two levels up to get the project root (helix_v3/)
HELIX_ROOT_DIR="$(realpath "$SCRIPT_DIR/../..")"
export HELIX_ROOT_DIR

# ─── Load Env Loader ───────────────────────────────────────────
ENV_LOADER_PATH="${HELIX_ROOT_DIR}/bootstrap_env_loader.sh"

if [[ ! -f "$ENV_LOADER_PATH" ]]; then
  echo "❌ ERROR: bootstrap_env_loader.sh not found at: $ENV_LOADER_PATH"
  exit 1
fi

# Save our HELIX_ROOT_DIR before sourcing env loader (which overwrites it)
SAVED_HELIX_ROOT_DIR="$HELIX_ROOT_DIR"
echo "Starting $ENV_LOADER_PATH"
source "$ENV_LOADER_PATH"
# Restore our correct HELIX_ROOT_DIR
HELIX_ROOT_DIR="$SAVED_HELIX_ROOT_DIR"
export HELIX_ROOT_DIR

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
source "${UTILS_DIR}/core/cluster_info.sh"
# ─── Load Deployment Phases ────────────────────────────────────
# ─── Start Timer ───────────────────────────────────────────────
START_TIME=$SECONDS
# # ─── Weather + Geo (For Vibes) ─────────────────────────────────
# echo ""
# echo "🌐 Gathering environment info..."
# HOST_IP=$(curl -s ifconfig.me || echo "Unknown")
# LINUX_INFO=$(uname -srvmo)
# DOCKER_VER=$(docker --version 2>/dev/null || echo "Docker not installed")
# CITY=$(curl -s https://ipinfo.io | jq -r '.city // "Unknown"')
# COUNTRY=$(curl -s https://ipinfo.io | jq -r '.country // "Unknown"')
# TEMP=$(curl -s "https://wttr.in/?format=j1" | jq -r '.current_condition[0].temp_C // "N/A"')
# echo "📍 ${CITY}, ${COUNTRY} — 🌡 ${TEMP}°C"
# echo "🐧 ${LINUX_INFO} • 🐳 ${DOCKER_VER}"
# echo ""
 
# ─── Flags ─────────────────────────────────────────────────────
DEBUG=false
SKIP_ERRORS=false
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --debug)       DEBUG=true ;;
    --skip-errors) SKIP_ERRORS=true ;;
    --dry-run)     DRY_RUN=true ;;
    *) echo "❌ Unknown option: $arg" && exit 1 ;;
  esac
done

export HELIX_DEBUG="${DEBUG}"
 
# ─── Error Handler ─────────────────────────────────────────────
error() {
  log_error "$1"
  echo "🕵️‍♂️ Hint: Did the script exist and have execute permissions?"
  echo "📂 CWD: $(pwd)"
  exit 1
}
# ─── Logging Setup ─────────────────────────────────────────────
if $DEBUG; then
  echo "🔍 Debug mode enabled. Verbose logging will be shown."
fi
# ─── Run Step Wrapper ──────────────────────────────────────────
run_step() {
  local name="$1"
  local script_path="$2"

  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  log_success "🔢 Running Step: $name"
  log_info "📜 Script: $script_path"
  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"

  if [[ ! -f "$script_path" ]]; then
    error "Script not found: $script_path"
  elif [[ ! -x "$script_path" ]]; then
    chmod +x "$script_path"
  fi

  if $DRY_RUN; then
    log_warn "🧪 Dry-run mode enabled: would execute $script_path"
    return 0
  fi

  "$script_path" || {
    if $SKIP_ERRORS; then
      log_warn "⚠️ Step '$name' failed but continuing..."
    else
      error "❌ Step '$name' failed"
    fi
  }

  log_success "✅ Step '$name' completed."
}

# ─── Menu Definitions ──────────────────────────────────────────
print_menu() {
  whiptail --title "Helix Orchestrator ${VERSION}" \
    --menu "Choose a deployment action:" 25 80 16 \
    "1" "🚀 Run All Core Steps (Fresh Cluster)" \
    "2" "📊 Create Cluster & Registry" \
    "3" "🔐 Generate TLS Certs" \
    "4" "👢 Bootstrap Vault & Unseal" \
    "5" "👤 Deploy Identity Stack (Postgres + Keycloak)" \
    "6" "🎨 Bootstrap Keycloak Realm & Theme" \
    "9" "📡 Cluster Health Check (watch mode)" \
    "A" "🐻 Keycloak Integrity Check" \
    "B" "➕ Add-On Plugin Installer" \
    "Q" "❌ Quit" 3>&1 1>&2 2>&3
}

# ─── Display Banner & Chuck Norris Quote ──────────────────────
# print_helix_banner "${VERSION}" "Deployment Orchestrator"
# cluster_info

# JOKE=$(curl -s https://api.chucknorris.io/jokes/random | jq -r '.value' || echo "Chuck Norris installed Helm by blinking.")
# echo "📣 Chuck Norris: $JOKE"
# echo ""
# print_deploy_footer
# ─── Main Menu Loop ────────────────────────────────────────────
while true; do
  CHOICE=$(print_menu)
  exit_status=$?

  if [[ $exit_status -ne 0 || "$CHOICE" == "Q" ]]; then
    log_info "👋 Exiting Helix Orchestrator."
    break
  fi

  case "$CHOICE" in
    1)
      run_step "01. Create Cluster & Registry" "${DEPLOY_PHASES_DIR}/01_create-cluster.sh"
      run_step "02. Generate TLS Certs" "${DEPLOY_PHASES_DIR}/generate_core_tls_certs.sh"
      run_step "03. Bootstrap Vault & Unseal" "${DEPLOY_PHASES_DIR}/03-vault-bootstrap-unseal.sh"
      ;;
    2)
      run_step "01. Create Cluster & Registry" "${DEPLOY_PHASES_DIR}/01_create-cluster.sh"
      ;;
    3)
      run_step "02. Generate TLS Certs" "${DEPLOY_PHASES_DIR}/generate_core_tls_certs.sh"
      ;;
    4)
      run_step "03. Bootstrap Vault & Unseal" "${DEPLOY_PHASES_DIR}/03-vault-bootstrap-unseal.sh"
    ;;
    5)
      run_step "04. Deploy Identity Stack" "${DEPLOY_PHASES_DIR}/04-deploy-identity-stack.sh"
      ;;
    6)
      run_step "05. Bootstrap Keycloak Realm & Theme" "${DEPLOY_PHASES_DIR}/05-bootstrap-keycloak-realm.sh"
      ;;
    7)
      run_step "06. Deploy Any Service via YAML" "${DEPLOY_PHASES_DIR}/utils/addons/install-service.sh"
      ;;
    8)
      run_step "07. Deploy Any Service via YAML" "${DEPLOY_PHASES_DIR}/utils/addons/run_plugins_menu.sh"
      ;;
    9)
      run_step "Cluster Health Check" "${DEPLOY_PHASES_DIR}/cluster-health-deployment.sh"
      ;;
    A)
      run_step "Keycloak Integrity Check" "${DEPLOY_PHASES_DIR}/check-keycloak-integrity.sh"
    ;;
    B)
      "${DEPLOY_PHASES_DIR}/run_plugins_menu.sh"
      ;;
    *)
      log_error "Invalid choice: $CHOICE"
      ;;
  esac

  log_info "Press Enter to return to main menu..."
  read -r
  clear
done

# ─── Exit Summary ──────────────────────────────────────────────
ELAPSED=$((SECONDS - START_TIME))
echo -e "\n✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
echo "✅ Helix Bootstrap Complete in ${ELAPSED}s"
echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
echo "📜 Services (if deployed):"
echo " - Keycloak:    https://keycloak.helix"
echo " - Vault:       https://vault.helix"
echo " - Portainer:   https://portainer.helix"
echo " - Adminer:     https://adminer.helix"
echo " - Traefik:     https://traefik.helix/dashboard/"
echo " - Portal:      https://portal.helix"

print_deploy_footer
sleep 10
