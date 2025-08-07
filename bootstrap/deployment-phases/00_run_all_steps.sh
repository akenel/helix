#!/usr/bin/env bash
# 🧠 Helix Whip — bootstrap/deployment-phases/00_run_all_steps.sh
set -euo pipefail
shopt -s failglob
# ─── Version ───────────────────────────────────────────────────
VERSION="v0.0.3-beta"
echo "Running Helix Whip Script: ${BASH_SOURCE[0]} in $(dirname "${BASH_SOURCE[0]}")"
trap 'on_error $LINENO' ERR
echo "🔐 Helix Deployment Bootstrap — ${VERSION}"
# ─── Colors ────────────────────────────────────────────────────
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color
START_TIME=$SECONDS
# ─── Error Handling ────────────────────────────────────────────
on_error() {
  local lineno="$1"
  echo -e "${RED}❌ Error in ${0} on line ${lineno} — aborting.${NC}"
  print_deploy_footer
  exit 1
}

# ─── Flags ─────────────────────────────────────────────────────
DEBUG=false
SKIP_ERRORS=false
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --debug)       DEBUG=true ;;
    --skip-errors) SKIP_ERRORS=true ;;
    --dry-run)     DRY_RUN=true ;;
    *) echo -e "${RED}❌ Unknown option: $arg${NC}" && exit 1 ;;
  esac
done
export HELIX_DEBUG="${DEBUG}"
$DEBUG && echo -e "${YELLOW}🔍 Debug mode enabled. Verbose logging will be shown.${NC}"
# ─── Run Step Function ─────────────────────────────────────────
run_step() {
  local name="$1"
  local script_path="$2"
  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  log_success "🔢 Running Step: $name"
  log_info "📜 Script: $script_path"
  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  if [[ ! -f "$script_path" ]]; then
    log_error "Script not found: $script_path"
    return 1
  fi
  [[ ! -x "$script_path" ]] && chmod +x "$script_path"
  if $DRY_RUN; then
    log_warn "🧪 Dry-run mode: would execute $script_path"
    return 0
  fi
  "$script_path"
  local status=$?
  if [[ $status -ne 0 ]]; then
    if $SKIP_ERRORS; then
      log_warn "⚠️ Step '$name' failed but continuing..."
    else
      log_error "❌ Step '$name' failed"
      return $status
    fi
  fi
  log_success "✅ Step '$name' completed."
  return 0
}
# ─── Print Header ──────────────────────────────────────────────
print_deploy_header() {
  echo -e "${CYAN}✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  echo -e "🔐 Helix Deployment Bootstrap — ${VERSION}"
  echo -e "${CYAN}✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
}
# ─── Menu Options ──────────────────────────────────────────────
print_menu() {
  whiptail --title "Helix Orchestrator ${VERSION}" \
    --menu "Choose a deployment action:" 25 80 16 \
    "1" "🚀 Run All Core Steps (Fresh Cluster)" \
    "2" "📊 Create Cluster & Registry" \
    "3" "🔐 Generate TLS Certs" \
    "4" "👢 Bootstrap Vault & Unseal" \
    "5" "🔐 Install Postgres Keycloak and Import Realm + Theme" \
    "A" "🔍 Keycloak Integrity Check" \
    "B" "📡 Helix Popeye Validation" \
    "Q" "❌ Quit"  
}
# ─── Main Loop ─────────────────────────────────────────────────
main_menu_loop() {
  while true; do
    CHOICE=""
    exit_status=0
    
    if command -v whiptail >/dev/null 2>&1; then
      CHOICE=$(whiptail --title "Helix Orchestrator ${VERSION}" \
        --menu "Choose a deployment action:" 25 80 16 \
        "1" "🚀 Run All Core Steps (Fresh Cluster)" \
        "2" "📊 Create Cluster & Registry" \
        "3" "🔐 Generate TLS Certs" \
        "4" "👢 Bootstrap Vault & Unseal" \
        "5" "🔐 Install Postgres Keycloak and Import Realm + Theme" \
        "A" "🔍 Keycloak Integrity Check" \
        "B" "📡 Helix Popeye Validation" \
        "Q" "❌ Quit" 2>/dev/null) || exit_status=$?
    else
      echo "❌ whiptail not found. Falling back to manual input."
      echo "1) Run All Core Steps"
      echo "2) Create Cluster & Registry"
      echo "3) Generate TLS Certs"
      echo "4) Bootstrap Vault & Unseal"
      echo "5) Deploy Full Stack Postgres Keycloak"
      echo "A) Keycloak Integrity Check"
      echo "B) Helix Popeye Validation"
      echo "Q) Quit"
      read -rp "Please enter your choice [1-9, Q]: " CHOICE
      exit_status=0
    fi
    
    # Exit condition
    if [[ $exit_status -ne 0 || "${CHOICE^^}" == "Q" || -z "$CHOICE" ]]; then
      echo -e "\n👋 ${CYAN}Exiting Helix Orchestrator. Goodbye!${NC}"
      return 0
    fi
    
    echo -e "\n🔍 You selected: ${CYAN}$CHOICE${NC}\n"
    
    # Step handler - wrap in error handling
 #   set +e  # Temporarily disable exit on error for step execution
    case "${CHOICE^^}" in
      1)
        run_step "01. Create Cluster & Registry"         "${DEPLOY_PHASES_DIR}/01_create-cluster.sh" && \
        run_step "02. Generate TLS Certs"                "${DEPLOY_PHASES_DIR}/generate_core_tls_certs.sh" && \
        run_step "03. Bootstrap Vault & Unseal"          "${DEPLOY_PHASES_DIR}/03-vault-bootstrap-unseal.sh" && \
        run_step "04. Deploy Keycloak"                   "${DEPLOY_PHASES_DIR}/32_deploy-keycloak.sh"
        if [[ $? -eq 0 ]]; then
          echo -e "${GREEN}✅ All core steps completed successfully!${NC}"
          echo -e "📜 Services (if deployed):"
          echo -e " - Keycloak:    https://keycloak.helix"
        else
          echo -e "${RED}❌ One or more steps failed. Check logs above.${NC}"
        fi
        ;;
      2) run_step "01. Create Cluster & Registry"         "${DEPLOY_PHASES_DIR}/01_create-cluster.sh" ;;
      3) run_step "02. Generate TLS Certs"                "${DEPLOY_PHASES_DIR}/generate_core_tls_certs.sh" ;;
      4) run_step "03. Bootstrap Vault & Unseal"          "${DEPLOY_PHASES_DIR}/03-vault-bootstrap-unseal.sh" ;;
      5) run_step "04. Deploy Postgres and Keycloak"      "${DEPLOY_PHASES_DIR}/32_deploy-keycloak.sh" ;;
      A) run_step "🔍 Keycloak Integrity Check"          "${DEPLOY_PHASES_DIR}/check-keycloak-integrity.sh" ;;
      B) run_step "🥫 Helix Popeye Validation Report"    "${DEPLOY_PHASES_DIR}/validate-helix.sh" ;;
      *)
        echo -e "${RED}❌ Invalid choice: $CHOICE${NC}"
        echo -e "${YELLOW}Please select an option or Escape to Quit${NC}"
        ;;
    esac
    set -e  # Re-enable exit on error
    
    # Pause before returning to menu (with shorter timeout)
    if [[ -t 1 ]]; then
      echo -e "${CYAN}↩️  Press [Enter] to return to main menu (auto-continue in few seconds)...${NC}"
      if ! read -r -t 3; then
        echo -e "\n${YELLOW}⏱️  Auto-continuing to menu...${NC}"
       source "${DEPLOY_PHASES_DIR}/00_run_all_steps.sh"
      fi
    else
      echo "🕳️ Non-interactive mode detected — skipping pause."
      sleep 2
    fi
  done
}
# Run the main menu loop
# ─── Check Dependencies ────────────────────────────────────────
if ! command -v whiptail &>/dev/null; then
  echo -e "${RED}❌ whiptail not found. Please install it: sudo apt install whiptail${NC}"
  exit 1
else
  echo -e "${GREEN}✅ whiptail found. Proceeding...${NC}"
fi
# ─── Path Resolution ───────────────────────────────────────────
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
DEPLOY_PHASES_DIR="${SCRIPT_DIR}"
HELIX_ROOT_DIR="$(realpath "$SCRIPT_DIR/../..")"
export HELIX_ROOT_DIR
# ─── Load Env Loader ───────────────────────────────────────────
ENV_LOADER_PATH="${HELIX_ROOT_DIR}/bootstrap_env_loader.sh"
if [[ ! -f "$ENV_LOADER_PATH" ]]; then
  echo -e "${RED}❌ ERROR: bootstrap_env_loader.sh not found at: $ENV_LOADER_PATH${NC}"
  exit 1
fi
echo "🔧 Loading environment from: $ENV_LOADER_PATH"
SAVED_HELIX_ROOT_DIR="$HELIX_ROOT_DIR"
source "$ENV_LOADER_PATH"
HELIX_ROOT_DIR="$SAVED_HELIX_ROOT_DIR"
export HELIX_ROOT_DIR
# ─── Utility Load ──────────────────────────────────────────────
UTILS_DIR="${SCRIPT_DIR}/utils"
if [[ ! -d "$UTILS_DIR" ]]; then
  echo -e "${RED}❌ ERROR: utils directory missing at: $UTILS_DIR${NC}"
  exit 1
fi
source "${UTILS_DIR}/core/spinner_utils.sh"
source "${UTILS_DIR}/core/print_helix_banner.sh"
source "${UTILS_DIR}/core/deploy-footer.sh"
source "${UTILS_DIR}/bootstrap/cluster_info.sh"
main_menu_loop
# ─── Final Summary ─────────────────────────────────────────────
ELAPSED=$((SECONDS - START_TIME))
echo -e "\n✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
echo "✅ Helix Bootstrap Complete in ${ELAPSED}s"
echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
echo "📜 Services (if deployed):"
echo " - Keycloak:    https://keycloak.helix"

if command -v print_deploy_footer >/dev/null 2>&1; then
  print_deploy_footer 2>/dev/null || echo "🏁 Session ended."
else
  echo "🏁 Session ended."
fi

sleep 5
echo -e "${CYAN}👋 Thank you for using Helix Orchestrator!${NC}"
exit 0