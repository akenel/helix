#!/bin/bash
# \\wsl.localhost\Ubuntu\home\angel\helix_v3\whiptail\helix-menu.sh
# Source common configuration and utility functions
HELIX_BOOTSTRAP_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
source "${HELIX_BOOTSTRAP_DIR}/utils/core/config.sh"
source "${HELIX_BOOTSTRAP_DIR}/utils/print_helix_banner.sh" # For the banner
source "${HELIX_BOOTSTRAP_DIR}/utils/core/spinner_utils.sh" # For logging functions (log_info, log_success, log_error)

# Ensure whiptail is installed
if ! command -v whiptail &> /dev/null; then
    echo "Error: whiptail is not installed. Please install it (e.g., 'sudo apt-get install whiptail' on Debian/Ubuntu)."
    exit 1
fi

# Function to display the main menu
show_main_menu() {
    print_helix_banner # Assuming this prints your ASCII banner

    whiptail --title "HELIX Deployment Menu" \
             --menu "Choose an action:" 20 78 12 \
             "1" "Deploy Adminer/Portainer Ingress Routes (Step 4a)" \
             "2" "Run Pre-Deployment Checks" \
             "3" "Run Post-Deployment Ingress Checks" \
             "4" "Keycloak Integrity Check" \
             "5" "Other Deployment Step (e.g., Run '04-deploy-identity-stack.sh')" \
             "Q" "Quit" 3>&1 1>&2 2>&3
}

# Main loop for the menu
while true; do
    CHOICE=$(show_main_menu)

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
            "${HELIX_BOOTSTRAP_DIR}/utils/check-keycloak-integrity.sh"
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