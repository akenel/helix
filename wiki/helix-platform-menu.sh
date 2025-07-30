#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR
# 🎩 helix-platform-menu.sh — "The Royal Launcher" ⚔️helix-platform-menu.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🎛️ Helix Platform Launcher Menu
# ⚙️ Commands to bootstrap and audit platform
# 👑 Angel — July 2025
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail
# 📁 wiki/helix-platform-menu.sh
# 🧠 Simple launcher to Helix utilities

ROOT_DIR="${HOME}/helix_v3"
UTILS_DIR="${ROOT_DIR}/utils/core"

source "${UTILS_DIR}/spinner_utils.sh" || {
  echo "❌ Failed to source spinner_utils.sh from ${UTILS_DIR}"
  exit 1
}

# 📝 Command history logging
HISTORY_LOG="$HOME/.helix/helixctl.history.log"
mkdir -p "$(dirname "$HISTORY_LOG")"
echo "$(date +'%F %T') • $USER • helixctl $*" >> "$HISTORY_LOG"

# 🔧 Paths to known scripts
# Get absolute path to this script, then derive root
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$BASE_DIR/.." && pwd)"

UTILS_DIR="$ROOT_DIR/bootstrap/utils"
BOOTSTRAP_DIR="$ROOT_DIR/bootstrap"

# Source banner if it exists
BANNER_SCRIPT="$UTILS_DIR/print_helix_banner.sh"
if [[ -f "$BANNER_SCRIPT" ]]; then
  source "$BANNER_SCRIPT"
else
  echo "⚠️ Banner script not found at $BANNER_SCRIPT — continuing without banner."
  print_helix_banner() { :; }  # Dummy function
fi

declare -A SCRIPTS=(
  [health]="$UTILS_DIR/core/cluster-health-core.sh"

)

DEBUG=false

log() {
  $DEBUG && echo "🪵 DEBUG: $*"
}

announce() {
  echo -e "\n🔹 $1\n"
}

show_help() {
    print_helix_banner "Helix CLI • v0.0.0" "🧭 Identity & Secrets Toolkit"

cat <<EOF
🎛️ Helix Platform Launcher

Usage:
  ./helix-platform-menu.sh [options]

Options:
  --sync                One-shot initialization + secrets + health
  --gui                 Launch interactive TUI menu (whiptail)
  --init-realm          Run Keycloak realm + client bootstrap
  --init-users          Add users + assign roles
  --export-secrets      Extract Keycloak client secrets to Vault
  --health              Run cluster + identity audit
  --verify-helm         Validate required Helm releases
  --check-vault-agent   Validate Vault Injector webhook status
  --debug               Enable debug logs
  --help                Show this menu
  --status              Show status
  --version             Show Version
  
EOF
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🧪 Helm Release Verifier
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
verify_helm() {
  echo "🔍 Verifying Helm releases: keycloak, portainer, vault..."

  local releases=(keycloak portainer vault)
  for rel in "${releases[@]}"; do
    if helm list -A | grep -q "$rel"; then
      echo "✅ Helm release found: $rel"
    else
      echo "❌ Helm release missing: $rel"
    fi
  done
}

show_help() {

  cat <<EOF
Usage:
  helixctl [options]
  --sync                One-shot initialization + secrets + health
  --gui                 Launch interactive TUI menu (whiptail)
  --init-realm          Run Keycloak realm + client bootstrap
  --init-users          Add users + assign roles
  --export-secrets      Extract Keycloak client secrets to Vault
  --health              Run cluster + identity audit
  --verify-helm         Validate required Helm releases
  --check-vault-agent   Validate Vault Injector webhook status
  --debug               Enable debug logs
  --help                Show this menu
  --status              Show status
  --version             Show_version
EOF
}
show_version() {
  echo ""
  echo "📦 Version:     v0.0.1"
  echo "🧬 Git Commit:  $(git rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
  echo "⚙️  K3d:         $(k3d version | head -n 1 | awk '{print $3}' 2>/dev/null || echo 'n/a')"
  echo "🐳 Docker:      $(docker version --format '{{.Client.Version}}' 2>/dev/null || echo 'n/a')"
  echo "📅 Timestamp:   $(date)"
  echo ""
  exit 0
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🧪 Vault Agent Injector Webhook Checker
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
check_vault_agent() {
  echo "🔐 Checking for Vault Agent injector webhook..."

  if kubectl get mutatingwebhookconfiguration vault-helix-agent-injector-cfg &>/dev/null; then
    echo "✅ Found: vault-helix-agent-injector-cfg"
  else
    echo "❌ Injector webhook missing"
  fi

  echo "🔍 Checking vault-agent pods:"
  kubectl get pods -n vault | grep injector || echo "⚠️ No injector pods running"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🧪 Realm Status Checker
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
show_status() {
   echo "🔐 Realm check:"
  if kubectl get realms helix -n identity &>/dev/null; then
    echo "✅ Realm 'helix' exists"
  else
    echo "❌ Realm 'helix' missing"
  fi

  echo ""
  echo "🔐 Vault check:"
  if vault status &>/dev/null; then
    echo "✅ Vault is reachable"
  else
    echo "❌ Vault unreachable"
  fi

  echo ""
  echo "📦 Helm releases:"
  helm list -A | grep -E 'keycloak|portainer|vault' || echo "⚠️ None found"

  echo ""
  echo "🔁 Vault Agent Injector:"
  if kubectl get mutatingwebhookconfiguration vault-helix-agent-injector-cfg &>/dev/null; then
    echo "✅ Webhook found: vault-helix-agent-injector-cfg"
  else
    echo "❌ Webhook not found"
  fi

  echo ""
  echo "✅ Status complete."
  exit 0
}
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🧭  one-shot command to: Initialize realm Create users Export secrets Perform health check
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
sync_all() {
  print_helix_banner "Helix CLI • 🧭 Full Platform Sync"

  echo -e "\n🔄 Starting full sync..."

  for step in init_realm init_users export_secrets health; do
    echo -e "\n👉 Running step: $step"
    "${SCRIPTS[$step]}" --debug || {
      echo -e "\e[31m❌ Step '$step' failed. Aborting sync.\e[0m"
      exit 1
    }
  done

  echo -e "\n✅ Full sync complete!"
  exit 0
}

show_gui() {
  local OPTIONS
  OPTIONS=(
    "1" "Init Keycloak Realm"
    "2" "Create Users"
    "3" "Export Secrets to Vault"
    "4" "Cluster Health"
    "5" "Verify Helm"
    "6" "Check Vault Agent"
    "7" "Full Sync"
    "8" "Exit"
  )

  CHOICE=$(whiptail --title "Helix Platform Launcher" --menu "Choose an action" 20 60 10 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)

  case "$CHOICE" in
    1) "$0" --init-realm ;;
    2) "$0" --init-users ;;
    3) "$0" --export-secrets ;;
    4) "$0" --health ;;
    5) "$0" --verify-helm ;;
    6) "$0" --check-vault-agent ;;
    7) "$0" --sync ;;
    *) echo "Goodbye!"; exit 0 ;;
  esac
}



# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🧭 Option Parser
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
while [[ $# -gt 0 ]]; do
  case "$1" in
    --init-realm)
      bash "${SCRIPTS[init_realm]}"
      ;;
    --gui)
    show_gui
    ;;
    --init-users)
      bash "${SCRIPTS[init_users]}"
      ;;
    --export-secrets)
      bash "${SCRIPTS[export_secrets]}"
      ;;
    --health)
      bash "${SCRIPTS[health]}"
      ;;
    --verify-helm)
      verify_helm
      ;;
    --check-vault-agent)
      check_vault_agent
      ;;
    --debug)
      DEBUG=true
      ;;
    --version)
      show_version
      ;;
    --status)
      show_status
      ;;
    --sync)
      sync_all
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      echo "❌ Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
  shift
done

# Show menu if nothing provided
if [[ $# -eq 0 ]]; then
  show_help
fi
