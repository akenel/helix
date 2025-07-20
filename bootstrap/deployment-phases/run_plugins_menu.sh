#!/usr/bin/env bash
# 🧩 Helix Plugin Submenu (Whiptail)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(realpath "$SCRIPT_DIR/../..")"
INSTALLER="${ROOT_DIR}/bootstrap/addon-configs/install-service.sh"

select_plugin() {
  whiptail --title "🧩 Choose a Plugin" --menu "Pick one:" 20 60 10 \
    "n8n" "Workflow automation" \
    "portainer" "UI for container orchestration" \
    "Back" "Return to Main Menu" 3>&1 1>&2 2>&3
}

select_action() {
  whiptail --title "🎮 Choose Action" --menu "Choose what to do:" 20 60 10 \
    "install" "Install this plugin" \
    "validate-only" "Validate Helm values & chart" \
    "upgrade" "Upgrade the plugin" \
    "uninstall" "Uninstall the plugin" \
    "edit" "Edit plugin values.yaml" \
    "Back" "Choose a different plugin" 3>&1 1>&2 2>&3
}

while true; do
  PLUGIN=$(select_plugin)
  [[ $? -ne 0 || "$PLUGIN" == "Back" ]] && break

  while true; do
    ACTION=$(select_action)
    [[ $? -ne 0 || "$ACTION" == "Back" ]] && break

    echo ""
    echo "🛠️ Running: $INSTALLER --plug $PLUGIN --$ACTION --debug"
    "$INSTALLER" --plug "$PLUGIN" --$ACTION --debug || {
      whiptail --title "⚠️ Action Failed" --msgbox "Plugin: $PLUGIN\nAction: $ACTION\nCheck logs for details." 10 60
    }
  done
done
