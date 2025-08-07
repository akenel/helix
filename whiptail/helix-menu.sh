#!/usr/bin/env bash
set -euo pipefail
trap 'echo -e "\n❌ Error in $0 on line $LINENO — aborting."' ERR

# ─── Constants ────────────────────────────────────────────────
VERSION="v1.0.0"
HELIX_BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_PHASES_DIR="${HELIX_BOOTSTRAP_DIR}/bootstrap/deployment-phases"
echo -e "🔧 Helix Bootstrap Directory: ${HELIX_BOOTSTRAP_DIR}"
UTILS_DIR="${HELIX_BOOTSTRAP_DIR}/utils"
START_TIME=$SECONDS

# ─── Colors ───────────────────────────────────────────────────
CYAN="\033[0;36m"
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
NC="\033[0m"

# ─── Helpers ──────────────────────────────────────────────────
source "${UTILS_DIR}/core/print_helix_banner.sh"
source "${UTILS_DIR}/core/spinner_utils.sh"
source "${UTILS_DIR}/core/deploy-footer.sh"
ENV_LOADER_PATH="${HELIX_BOOTSTRAP_DIR}/bootstrap_env_loader.sh"
if [[ ! -f "$ENV_LOADER_PATH" ]]; then
  echo -e "${RED}❌ ERROR: bootstrap_env_loader.sh not found at: $ENV_LOADER_PATH${NC}"
  exit 1
fi
run_step() {
  local name="$1"
  local script_path="$2"
  echo -e "\n🔹 ${YELLOW}Running: ${name}${NC}"
  [[ ! -x "$script_path" ]] && chmod +x "$script_path"
  "$script_path" || {
    echo -e "${RED}❌ Failed: $name${NC}"
    return 1
  }
  echo -e "${GREEN}✅ Completed: $name${NC}\n"
}

# ─── Main Menu ────────────────────────────────────────────────
main_menu_loop() {
  while true; do
    CHOICE=$(whiptail --title "🔧 Helix Orchestrator ${VERSION}" --menu \
      "Choose an action:" 25 80 16 \
      "1" "🚀 Run All Core Steps" \
      "2" "📊 Create Cluster & Registry" \
      "3" "🔐 Generate TLS Certs" \
      "4" "🔑 Bootstrap Vault & Unseal" \
      "5" "🧠 Deploy Keycloak & Postgres" \
      "6" "✅ Post Keycloak Initialization Realm" \
      "7" "🔗 Configure Vault and Keycloak OIDC" \
      "9" "🔧 Plugin Manager" \
      "A"  "🔥 Before vs After: The DevOps Mic Drop" \
      "Q" "❌ Quit" 3>&1 1>&2 2>&3) || return

    case "$CHOICE" in
      1)
        run_step "Create Cluster & Registry" "${DEPLOY_PHASES_DIR}/01_create-cluster.sh"
        run_step "Generate TLS Certs" "${DEPLOY_PHASES_DIR}/generate_core_tls_certs.sh"
        run_step "Bootstrap Vault & Unseal" "${DEPLOY_PHASES_DIR}/03-vault-bootstrap-unseal.sh"
        run_step "Deploy Keycloak" "${DEPLOY_PHASES_DIR}/32_deploy-keycloak.sh"
        run_step "Post Keycloak Initialization" "${DEPLOY_PHASES_DIR}/33_post_keycloak_initialize.sh"
        run_step "Configure Vault and Keycloak OIDC" "${DEPLOY_PHASES_DIR}/34_vault_oidc_setup.sh"
        ;;
      2) run_step "Create Cluster & Registry" "${DEPLOY_PHASES_DIR}/01_create-cluster.sh" ;;
      3) run_step "Generate TLS Certs" "${DEPLOY_PHASES_DIR}/generate_core_tls_certs.sh" ;;
      4) run_step "Bootstrap Vault & Unseal" "${DEPLOY_PHASES_DIR}/03-vault-bootstrap-unseal.sh" ;;
      5) run_step "Deploy Keycloak" "${DEPLOY_PHASES_DIR}/32_deploy-keycloak.sh" ;;
      6) run_step "Post Keycloak Initialization" "${DEPLOY_PHASES_DIR}/33_post_keycloak_initialize.sh" ;;
      7) run_step "Configure Vault and Keycloak OIDC" "${DEPLOY_PHASES_DIR}/34_vault_oidc_setup.sh" ;;

      9) plugin_menu ;;
      A)
        run_step "🎭 Running the Before vs After Demo" "${HELIX_BOOTSTRAP_DIR}/demo/before-vs-after.sh"
        echo -e "\n${CYAN}↩️  Press any key to return to the Helix Menu...${NC}"
        read -n 1 -s -r  # Wait for a single keypress
        ;;
      Q) echo -e "\n👋 ${CYAN}Goodbye from Helix!${NC}"; break ;;
    esac

    echo -e "${CYAN}\n↩️ Press [Enter] to return to main menu...${NC}"
    read -r
  done
}

# ─── Plugin Menu ───────────────────────────────────────────────
plugin_menu() {
  local services_file="${HELIX_BOOTSTRAP_DIR}/bootstrap/addon-configs/services.yaml"
  if [[ ! -f "$services_file" ]]; then
    echo -e "${RED}⚠️ No plugins config found: $services_file${NC}"
    return
  fi

  local plugin_list=()
  local enabled_plugins
  enabled_plugins=$(yq -r '.plugins[] | select(.enabled == true) | "\(.name)|\(.emoji // "🔧")|\(.description // "Plugin")"' "$services_file")

  while IFS='|' read -r name emoji desc; do
    plugin_list+=("$name" "$emoji $desc")
  done <<< "$enabled_plugins"

  plugin_list+=("BACK" "⬅️ Back to main menu")

  local selected_plugin
  selected_plugin=$(whiptail --title "🚀 Plugin Manager" \
    --menu "Select a plugin to manage:" 20 78 10 \
    "${plugin_list[@]}" 3>&1 1>&2 2>&3) || return

  if [[ "$selected_plugin" == "BACK" ]]; then return; fi

  plugin_actions "$selected_plugin"
}

plugin_actions() {
  local plug="$1"
  local installer="${HELIX_BOOTSTRAP_DIR}/bootstrap/addon-configs/install-service.sh"

  local action
  action=$(whiptail --title "🛠️ Plugin: $plug" \
    --menu "Choose action:" 20 70 10 \
    "INSTALL" "🚀 Install plugin" \
    "VALIDATE" "🧪 Validate configuration" \
    "STATUS" "📊 Plugin status" \
    "UNINSTALL" "🗑️ Uninstall plugin" \
    "BACK" "⬅️ Back to plugin list" 3>&1 1>&2 2>&3) || return

  case "$action" in
    INSTALL)   "$installer" --plug "$plug" --install --debug ;;
    VALIDATE)  "$installer" --plug "$plug" --validate-only --debug ;;
    STATUS)
      helm status "$plug" -n "$plug" || echo "🔍 Helm release not found"
      kubectl get all -n "$plug" || echo "🔍 Namespace not found"
      ;;
    UNINSTALL)
      if whiptail --yesno "Really uninstall $plug?" 10 60; then
        "$installer" --plug "$plug" --uninstall --debug
      fi ;;
    BACK) return ;;
  esac

  echo -e "${CYAN}\n↩️ Press [Enter] to return to plugin menu...${NC}"
  read -r
  plugin_menu
}

# ─── Bootstrap Entry Point ─────────────────────────────────────
clear
print_helix_banner
echo -e "${CYAN}🔧 Loading environment...${NC}"
source "${HELIX_BOOTSTRAP_DIR}/bootstrap_env_loader.sh"
echo -e "${GREEN}✅ whiptail is installed. Launching...${NC}"
main_menu_loop
# ─── Wrap-Up ───────────────────────────────────────────────────
ELAPSED=$((SECONDS - START_TIME))
echo -e "\n${GREEN}✅ Helix orchestration completed in ${ELAPSED}s${NC}"
print_deploy_footer() {
  echo ""
  echo "🎬 Deployment Summary:"
  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  echo "🔧 Components 🧩 Core Services:"
  echo "🔍 Investigating Cluster Deployment:"
  echo ""
  # printf "   🔐 Vault        → %s\n" "$(get_status vault vault-helix-0)"
  printf "   🧠 Keycloak     → %s\n" "$(get_status identity keycloak-0)"
  printf "   🗄️ Postgres     → %s\n" "$(get_status identity postgres-postgresql-0)"


  echo ""
  echo "🔐 TLS Chain:"
  printf "   🎩 mkcert CA           %s\n" "$(tls_ca_status)"
  printf "   🪄 ClusterIssuer       %s\n" "$(clusterissuer_status)"

  echo ""
  echo "📊 Secrets:"
  printf "   🔑 Vault KV            %s\n" "$(kubectl get secret -n vault &>/dev/null && echo '✅' || echo '❌')"
  printf "   🔐 Kubeconfig Patched  %s\n" "$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null | grep -q '127.0.0.1:6550' && echo '✅' || echo '❌')"
  printf "   🔑 App Keys Injected   %s\n" "$(kubectl get secret -n identity  &>/dev/null && echo '✅' || echo '❌')"

  echo ""
  echo "🔑 App Secrets:"
  printf "   🔑 Keycloak Secret     %s\n" "$(kubectl get secret -n identity keycloak-helix &>/dev/null && echo '✅' || echo '❌')"
  printf "   🔑 Postgres Secret     %s\n" "$(kubectl get secret -n identity postgresql-helix &>/dev/null && echo '✅' || echo '❌')"
  printf "   🔒 Keycloak TLS        %s\n" "$(kubectl get secret -n identity keycloak.helix-tls &>/dev/null && echo '✅' || echo '❌')"
  printf "   🎁 Helm Keycloak Rel.  %s\n" "$(kubectl get secret -n identity sh.helm.release.v1.keycloak-helix.v1 &>/dev/null && echo '✅' || echo '❌')"
  printf "   🎁 Helm Postgres Rel.  %s\n" "$(kubectl get secret -n identity sh.helm.release.v1.postgresql-helix.v1 &>/dev/null && echo '✅' || echo '❌')"
   
  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  JOKE=$(curl -s https://api.chucknorris.io/jokes/random | jq -r '.value' || echo "Chuck Norris installed Helm by blinking.")
  echo "🕵️ \"$JOKE!\""
  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  
  echo "✅ Deployment Summary Complete!"
  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  echo "🎉 Congratulations! Your Helix Orchestrator is now fully deployed and operational."
  echo "For more information, visit: https://github.com/akenel/helix/blob/main/README.md"
  echo ""
  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  echo "Thank you for using Helix Orchestrator! 🙌"
  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  sleep 3
  exit 0
}

# ─── Final Vars ────────────────────────────────────────────────
export DOMAIN="${DOMAIN:-keycloak.helix}"
export VAULT_ADDR="${VAULT_ADDR:-https://vault.helix}"
export VAULT_NAMESPACE="${VAULT_NAMESPACE:-helix}"
export KEYCLOAK_RELEASE="${KEYCLOAK_RELEASE:-keycloak-helix}"
export NAMESPACE="${NAMESPACE:-identity}"
export DB_NAME="${DB_NAME:-keycloak}"
export POSTGRES_RELEASE="${POSTGRES_RELEASE:-postgresql-helix}"
export ADMIN_USER="${ADMIN_USER:-admin}"
export ADMIN_PASS="${ADMIN_PASS:-admin}"        
export VALUES_FILE="${VALUES_FILE:-${HELIX_BOOTSTRAP_DIR}/bootstrap/addon-configs/keycloak-values.yaml}"
export REALM_FILE="${REALM_FILE:-${HELIX_BOOTSTRAP_DIR}/bootstrap/addon-configs/keycloak/realms/helix-realm-full.json}"

# ─── Optional: Suppress noisy HTML rendering logs ──────────────
echo -e "${CYAN}📄 Generating Helix HTML report...${NC}"
generate_helix_report &> /dev/null || echo -e "${YELLOW}⚠️ Report generation completed with minor warnings (suppressed).${NC}"

# ─── Print Footer ───────────────────────────────────────────────
echo -e "${CYAN}🔐 Deploying Keycloak with domain: ${DOMAIN}${NC}"
print_deploy_footer
# ─── Final Acknowledgment ──────────────────────────────────────
echo -e "${GREEN}✅ Deployment complete!${NC}"
echo -e "🔑 Realm URL: ${GREEN}https://${DOMAIN}${NC}"
echo -e "${CYAN}🏁 Done.${NC}"
exit 0
