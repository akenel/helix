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
    
    # Capture the start time for log file identification
    TIMESTAMP=$(date +%s)
    
    if "$INSTALLER" --plug "$PLUGIN" --$ACTION --debug; then
      echo "✅ Plugin $PLUGIN $ACTION completed successfully!"
    else
      # Find the most recent log file for this plugin and action
      LOG_FILE=$(find "$ROOT_DIR/logs" -name "${PLUGIN}-${ACTION}-*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
      
      if [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]]; then
        echo ""
        echo "❌ Plugin installation failed!"
        echo "📂 Log file: $LOG_FILE"
        echo ""
        echo "📋 Last 15 lines of log:"
        echo "─────────────────────────────────────────"
        tail -15 "$LOG_FILE" 2>/dev/null || echo "Could not read log file"
        echo "─────────────────────────────────────────"
        echo ""
        echo "💡 Commands to investigate:"
        echo "   cat \"$LOG_FILE\""
        echo "   kubectl get pods -n $PLUGIN"
        echo "   kubectl describe pod -n $PLUGIN"
        echo ""
        read -p "Press Enter to continue or Ctrl+C to exit..."
      else
        whiptail --title "⚠️ Action Failed" --msgbox "Plugin: $PLUGIN\nAction: $ACTION\nNo log file found - check manually in logs/ directory." 12 70
      fi
    fi
  done
done
