#!/bin/bash
# \\wsl.localhost\Ubuntu\home\angel\helix_v3\whiptail\helix-menu.sh
# Source common configuration and utility functions
HELIX_BOOTSTRAP_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
source "${HELIX_BOOTSTRAP_DIR}/utils/core/config.sh"
source "${HELIX_BOOTSTRAP_DIR}/utils/core/print_helix_banner.sh" # For the banner
source "${HELIX_BOOTSTRAP_DIR}/utils/core/spinner_utils.sh" # For logging functions (log_info, log_success, log_error)

# Ensure whiptail is installed
if ! command -v whiptail &> /dev/null; then
    echo "Error: whiptail is not installed. Please install it (e.g., 'sudo apt-get install whiptail' on Debian/Ubuntu)."
    exit 1
fi

# Function to display the main menu
show_main_menu() {
    # Don't clear the terminal - preserve the beautiful output!
    echo "" >&2
    echo "🎯 Returning to HELIX Menu..." >&2
    echo "" >&2
    
    # Print banner but not on initial run if output exists
    if [[ "${FIRST_RUN:-true}" == "true" ]]; then
        print_helix_banner >&2 # Show banner only on first run
        FIRST_RUN=false
    fi

    whiptail --title "HELIX Deployment Menu" \
             --menu "Choose an action:" 24 80 11 \
             "1" "Deploy Adminer/Portainer Ingress Routes (Step 4a)" \
             "2" "Run Pre-Deployment Checks" \
             "3" "Run Post-Deployment Ingress Checks" \
             "4" "Keycloak Integrity Check" \
             "5" "Other Deployment Step" \
             "6" "🔥 EPIC DEMO: Before vs After" \
             "7" "🥫 Popeye Enterprise Validation" \
             "8" "🩺 Cluster Health Check" \
             "9" "🚀 Plugin Manager" \
             "C" "🧹 Clear Screen" \
             "Q" "Quit" 3>&1 1>&2 2>&3
}

# Function to show plugin management menu
show_plugin_menu() {
    local services_file="${HELIX_BOOTSTRAP_DIR}/bootstrap/addon-configs/services.yaml"
    
    if [[ ! -f "$services_file" ]]; then
        log_error "Services configuration file not found: $services_file"
        return 1
    fi
    
    # Build plugin list dynamically from services.yaml
    local plugin_list=()
    local enabled_plugins
    
    # Get enabled plugins with their emojis and descriptions
    enabled_plugins=$(yq -r '.plugins[] | select(.enabled == true) | "\(.name)|\(.emoji // "🔧")|\(.description // "No description")"' "$services_file" 2>/dev/null)
    
    if [[ -z "$enabled_plugins" ]]; then
        log_error "No enabled plugins found in services.yaml"
        return 1
    fi
    
    # Build whiptail menu array
    while IFS='|' read -r name emoji desc; do
        plugin_list+=("$name" "$emoji $desc")
    done <<< "$enabled_plugins"
    
    # Add management options
    plugin_list+=("LIST" "📦 List all available plugins")
    plugin_list+=("BACK" "⬅️ Back to main menu")
    
    local selected_plugin
    selected_plugin=$(whiptail --title "🚀 Plugin Manager" \
                              --menu "Select a plugin to manage:" 20 78 10 \
                              "${plugin_list[@]}" 3>&1 1>&2 2>&3)
    
    if [[ $? -ne 0 ]]; then
        return 0  # User cancelled
    fi
    
    case "$selected_plugin" in
        "LIST")
            log_info "📦 Listing all available plugins..."
            "${HELIX_BOOTSTRAP_DIR}/bootstrap/addon-configs/install-service.sh" --list
            log_info "Press Enter to continue..."
            read -r
            ;;
        "BACK")
            return 0
            ;;
        *)
            show_plugin_actions "$selected_plugin"
            ;;
    esac
}

# Function to show actions for a specific plugin
show_plugin_actions() {
    local plugin_name="$1"
    
    local action_menu=(
        "VALIDATE" "🧪 Validate plugin configuration"
        "INSTALL" "🚀 Install plugin"
        "UPGRADE" "⬆️ Upgrade plugin"
        "UNINSTALL" "🗑️ Uninstall plugin"
        "STATUS" "📊 Check plugin status"
        "BACK" "⬅️ Back to plugin list"
    )
    
    local selected_action
    selected_action=$(whiptail --title "🚀 Plugin Manager - $plugin_name" \
                              --menu "Choose an action for $plugin_name:" 18 78 8 \
                              "${action_menu[@]}" 3>&1 1>&2 2>&3)
    
    if [[ $? -ne 0 || "$selected_action" == "BACK" ]]; then
        show_plugin_menu  # Return to plugin menu
        return 0
    fi
    
    local installer="${HELIX_BOOTSTRAP_DIR}/bootstrap/addon-configs/install-service.sh"
    
    case "$selected_action" in
        "VALIDATE")
            log_info "🧪 Validating $plugin_name configuration..."
            "$installer" --plug "$plugin_name" --validate-only --debug
            ;;
        "INSTALL")
            log_info "🚀 Installing $plugin_name..."
            "$installer" --plug "$plugin_name" --install --debug
            ;;
        "UPGRADE")
            log_info "⬆️ Upgrading $plugin_name..."
            "$installer" --plug "$plugin_name" --upgrade --debug
            ;;
        "UNINSTALL")
            if whiptail --title "⚠️ Confirm Uninstall" \
                       --yesno "Are you sure you want to uninstall $plugin_name?\n\nThis will remove all resources in the $plugin_name namespace." 10 60; then
                log_info "🗑️ Uninstalling $plugin_name..."
                "$installer" --plug "$plugin_name" --uninstall --debug
            else
                log_info "Uninstall cancelled."
            fi
            ;;
        "STATUS")
            log_info "📊 Checking $plugin_name status..."
            echo "=== Helm Release Status ==="
            helm status "$plugin_name" -n "$plugin_name" 2>/dev/null || echo "Release not found"
            echo ""
            echo "=== Kubernetes Resources ==="
            kubectl get all -n "$plugin_name" 2>/dev/null || echo "Namespace not found"
            ;;
    esac
    
    log_info "Press Enter to continue..."
    read -r
    show_plugin_actions "$plugin_name"  # Return to action menu
}

# Main loop for the menu
while true; do
    CHOICE=$(show_main_menu)
    
    # Debug: Show what choice was selected
    # echo "DEBUG: Selected choice: '$CHOICE'" >&2

    # Check the exit status of whiptail.
    # 0 for OK/selected, 1 for Cancel, 255 for ESC.
    if [[ $? -ne 0 ]]; then
        log_info "Operation cancelled by user or ESC pressed. Exiting menu."
        break
    fi

    case "$CHOICE" in
        1)
            log_info "Running 'Deploy Adminer/Portainer Ingress Routes'..."
            # Run your 4a script
            "${HELIX_BOOTSTRAP_DIR}/04a-ingress-route.sh"
            log_info "Ingress Route deployment attempt complete. Press Enter to continue..."
            read -r # Wait for user input before returning to menu
            ;;
        2)
            log_info "Running Pre-Deployment Checks..."
            # You would put relevant checks here. For example, ensure cert-manager is ready,
            # Traefik is ready, Vault is unsealed etc.
            log_info "Checking Traefik Ingress Controller status..."
            if kubectl get pods -n traefik -l app.kubernetes.io/name=traefik --field-selector=status.phase=Running | grep -q "traefik"; then
                log_success "Traefik Ingress Controller pods are running."
            else
                log_error "Traefik Ingress Controller pods are NOT running. Ingress might not work."
            fi
            log_info "Pre-deployment checks complete. Press Enter to continue..."
            read -r
            ;;
        3)
            log_info "Running Post-Deployment Ingress Checks (from 04a-ingress-route.sh)..."
            # This is where you would call specific check functions, or wrap the checks
            # part of 04a-ingress-route.sh into a separate script, e.g., 04a-check-ingress.sh
            # For simplicity, let's just re-run the checks from 04a-ingress-route.sh
            # (you'd ideally factor them out into a separate reusable script).
            "${HELIX_BOOTSTRAP_DIR}/04a-ingress-route.sh" # This runs the full script, including checks.
                                                          # Ideally, you'd have a separate function/script for just checks.
            log_info "Post-deployment Ingress checks complete. Press Enter to continue..."
            read -r
            ;;
        4)
            log_info "Running Keycloak Integrity Check..."
            "${HELIX_BOOTSTRAP_DIR}/core/check-keycloak-integrity.sh"
            log_info "Keycloak integrity check complete. Press Enter to continue..."
            read -r
            ;;
        5)
            log_info "Running Other Deployment Step..."
            # Example: Allow user to run another script
            OTHER_SCRIPT=$(whiptail --inputbox "Enter path to script to run (e.g., ./04-deploy-identity-stack.sh):" 10 60 3>&1 1>&2 2>&3)
            if [[ $? -eq 0 && -n "$OTHER_SCRIPT" && -f "$OTHER_SCRIPT" ]]; then
                log_info "Executing $OTHER_SCRIPT..."
                "$OTHER_SCRIPT"
            else
                log_warn "No script entered or script not found. Skipping."
            fi
            log_info "Other deployment step complete. Press Enter to continue..."
            read -r
            ;;
        6)
            log_info "🔥 Launching EPIC Before vs After Demo - The DevOps World Breaker!"
            log_info "⚠️  WARNING: This demo has caused enterprise architects to question their careers!"
            "${HELIX_BOOTSTRAP_DIR}/demo/before-vs-after.sh"
            log_info "🎉 Demo complete! Share this with every developer you know!"
            log_info "Press Enter to continue..."
            read -r
            ;;
        7)
            log_info "🥫 Running Popeye Enterprise Validation..."
            log_info "💪 Popeye says: 'I yam what I yam, and Helix beats enterprise!'"
            "${HELIX_BOOTSTRAP_DIR}/utils/core/validate-helix.sh"
            log_info "✅ Popeye validation complete! Check the viral HTML report!"
            log_info "Press Enter to continue..."
            read -r
            ;;
        8)
            log_info "🩺 Running Cluster Health Check with Live Status..."
            log_info "🎯 Real-time status tracking and Popeye integration!"
            "${HELIX_BOOTSTRAP_DIR}/utils/core/cluster-health-check.sh"
            log_info "✅ Health check complete! All systems monitored!"
            log_info "Press Enter to continue..."
            read -r
            ;;
        9)
            log_info "🚀 Launching Plugin Manager..."
            show_plugin_menu
            ;;
        C)
            clear
            log_info "🧹 Screen cleared! Fresh start..."
            FIRST_RUN=true  # Show banner again after clear
            ;;
        Q)
            log_info "Exiting Helix Deployment Menu. Goodbye!"
            exit 0
            ;;
        *)
            log_error "Invalid option '$CHOICE'. Please try again."
            log_info "Press Enter to continue..."
            read -r
            ;;
    esac
done