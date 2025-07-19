#!/bin/bash
# 🧠 Helix Master Orchestrator — ./run.sh
# Sherlock-Holmes Edition 🕵️‍♂️

set -euo pipefail
echo "🚀 RUNNING: \helix_v3\run.sh"
# ─────────────────────────────────────────────────────────────
# 🕰️ Start time tracking
start_time=$(date +%s)

# 📌 Environment & Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="${SCRIPT_DIR}/bootstrap"
PHASE_DIR="${BOOTSTRAP_DIR}/deployment-phases"
UTILS_DIR="${SCRIPT_DIR}/utils/bootstrap"
WHIPTAIL_MENU="${SCRIPT_DIR}/whiptail/helix-menu.sh"
echo "UTILS_DIR $UTILS_DIR"
# ─────────────────────────────────────────────────────────────
# 🏷️ Flag Defaults
HELP=false
DEBUG=false
POST_MENU=false
DRY_RUN=false
ONLY_SUCCESS=false
QUIET=false

# ─────────────────────────────────────────────────────────────
# 🏷️ Flag Parser
for arg in "$@"; do
  case "$arg" in
    --help|-h)        HELP=true ;;
    --debug|-d)       DEBUG=true ;;
    --plan|--dry-run) DRY_RUN=true ;;
    --post-menu)      POST_MENU=true ;;
    --success|-s)     ONLY_SUCCESS=true ;;
    --quiet|-q)       QUIET=true ;;
    *) echo "❌ Unknown flag: $arg"; HELP=true ;;
  esac
done

# ─────────────────────────────────────────────────────────────
# 📖 Help Message
if $HELP; then
  echo ""
  echo "🧠 Helix Bootstrap Usage"
  echo "Usage: ./run.sh [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --debug, -d       Enable debug mode"
  echo "  --plan, --dry-run Show execution plan without running scripts"
  echo "  --post-menu       Show whiptail post-menu after bootstrap"
  echo "  --success, -s     Only run successful phases"
  echo "  --quiet, -q       Minimal output"
  echo "  --help, -h        Show this help message"
  echo ""
  exit 0
fi

# ─────────────────────────────────────────────────────────────
# 🧠 Run Introduction
echo -e "\n📁 ROOT RUN 🧠 based location."
echo "🐳 Using Deployment Phases: ${PHASE_DIR}"
sleep .2
$DEBUG && echo "🧪 [DEBUG] Mode Activated"

# 🧩 Phase discovery
PHASES=($(find "$PHASE_DIR" -maxdepth 1 -name "*.sh" | sort))

# ─────────────────────────────────────────────────────────────
# 🔁 Run Each Phase
for phase_script in "${PHASES[@]}"; do
  PHASE_NAME="$(basename "$phase_script")"
  echo -e "\n📅 $(date '+%Y-%m-%d %H:%M:%S') — 🔹 Running Phase: ${PHASE_NAME}"
  echo "📁 Script: $phase_script 🐳"
  sleep .5
  if $DRY_RUN; then
    echo "🔍 Dry run enabled — skipping execution"
    continue
  fi

  if $DEBUG; then
    DEBUG=true "$phase_script"
  else
    "$phase_script"
  fi
done

# ─────────────────────────────────────────────────────────────
# 🕓 Runtime Report
end_time=$(date +%s)
elapsed=$((end_time - start_time))
echo -e "\n✅ All Phases Complete — Total Duration: $(date -u -d @$elapsed +%T)"

# ─────────────────────────────────────────────────────────────
# 🎯 Optional Whiptail Menu
if $POST_MENU && [ -f "$WHIPTAIL_MENU" ]; then
  bash "$WHIPTAIL_MENU"
fi
