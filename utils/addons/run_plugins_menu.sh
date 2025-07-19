#!/bin/bash
# bootstrap\utils\run_plugins_menu.sh
set -euo pipefail
echo "🚀 RUNNING: helix_v3\bootstrap\utils\run_plugins_menu.sh"
CONFIG_FILE="${HELIX_ROOT_DIR}/bootstrap/addon-configs/services.yaml"
INSTALL_SCRIPT="${HELIX_ROOT_DIR}/bootstrap/addon-configs/install-service.sh"
sleep 8
# Use yq to list enabled plugins
PLUGINS=($(yq -r '.plugins[] | select(.enabled == true) | .name' "$CONFIG_FILE"))

if [ ${#PLUGINS[@]} -eq 0 ]; then
  echo "⚠️ No enabled plugins found in $CONFIG_FILE"
  exit 1
fi

CHOICE=$(whiptail --title "📦 Add-On Installer" --menu "Select a plugin to install:" 20 60 10 \
$(for plugin in "${PLUGINS[@]}"; do
    DESC=$(yq -r ".plugins[] | select(.name == \"${plugin}\") | .description" "$CONFIG_FILE")
    EMOJI=$(yq -r ".plugins[] | select(.name == \"${plugin}\") | .emoji" "$CONFIG_FILE")
    echo "$plugin" "$EMOJI $DESC"
done) \
3>&1 1>&2 2>&3)

if [[ -n "$CHOICE" ]]; then
  echo "🚀 Installing plugin: $CHOICE"
  bash "$INSTALL_SCRIPT" --plug "$CHOICE" --debug
else
  echo "❌ No plugin selected. Returning to main menu."
fi
