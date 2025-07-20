#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

# 🔧 Helix Plugin Installer – Sherlock Edition
set -euo pipefail
IFS=$'\n\t'

# --- Global Variables ---
# These variables are declared here and used throughout the script and sourced helpers.
# Initialized empty; populated by parse_args and get_and_validate_plugin_details
ACTION=""
DEBUG=false
SERVICE=""
NAME=""
NAMESPACE=""
VALUES_PATH=""
HELM_INSTALL_CMD=""
HELM_UPGRADE_CMD=""
NOTES=""
DEFAULT_STORAGE_CLASS=""

# --- Path Variables (These must be set early) ---
# SCRIPT_PATH uses realpath to resolve symlinks and get the absolute path of the script.
SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
# ROOT_DIR assumes the script is located at <repo_root>/bootstrap/addon-configs
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)" 

CONFIG_FILE="$ROOT_DIR/bootstrap/addon-configs/services.yaml"
LOG_DIR="$ROOT_DIR/logs" # Centralized log directory at the root of the repo
FULL_LOG_FILE="" # Will be populated in main() after NAME is known

# --- Source Helper Scripts ---
# Source order matters:
# 1. display.sh: Provides print_info, print_error, etc., which are used by almost all other scripts.
# 2. spinner.sh: Provides the spin function, used by deployment.sh.
# 3. parsing.sh: Provides parse_args, normalize_helm_command, run_plugin_wizard.
# 4. validation.sh: Provides validation functions that might use parsing functions (e.g., normalize_helm_command).
# 5. deployment.sh: Provides deployment functions that rely on parsing and validation results.
source "$SCRIPT_DIR/helpers/display.sh"
source "$ROOT_DIR/utils/core/spinner.sh"
source "$SCRIPT_DIR/helpers/parsing.sh"
source "$SCRIPT_DIR/helpers/validation.sh"
source "$SCRIPT_DIR/helpers/deployment.sh"

# --- Main Entry ---
main() {
    # Validate core environment before parsing args or doing anything else.
    # This ensures essential tools (helm, kubectl, yq) and directories are present.
    validate_env

    # Parse command-line arguments. This populates global ACTION, DEBUG, SERVICE.
    parse_args "$@"

    # Dispatch based on the determined ACTION
    case "$ACTION" in
        list)
            print_info "📦 Available Plugins:"
            # Use yq to list enabled plugins with their names and descriptions from the config file.
            if yq -r '.plugins[] | select(.enabled==true) | "• \(.name): \(.description)"' "$CONFIG_FILE"; then
                print_success "Plugin listing complete."
            else
                # If yq fails or no plugins are found, print an error.
                print_error "Failed to list plugins from '$CONFIG_FILE'." "Check YAML syntax or 'plugins' array structure in '$CONFIG_FILE'." 1
            fi
            exit 0
            ;;

        create)
            # Run the interactive wizard to create a new plugin entry in services.yaml.
            run_plugin_wizard
            exit 0
            ;;

        edit)
            # Ensure a plugin name is provided for editing.
            if [[ -z "$SERVICE" ]]; then
                print_error "Plugin name is required for 'edit' action." "Use --plug <plugin_name>." 1
            fi
            # Get plugin details; this populates NAME, VALUES_PATH etc.
            get_and_validate_plugin_details "$SERVICE"
            print_info "✏️ Editing values file for '$NAME': $(realpath "$VALUES_PATH")"
            # Open the values file in the user's preferred editor (EDITOR env var) or nano as fallback.
            "${EDITOR:-nano}" "$(realpath "$VALUES_PATH")" || print_error "Failed to open editor for '$VALUES_PATH'." "Check EDITOR environment variable or permissions." 1
            print_success "Values file edited. Remember to validate changes, possibly with '$0 --plug $NAME --validate-only'."
            exit 0
            ;;

        # Actions that require a specific plugin and involve Helm operations
        install|upgrade|validate-only|uninstall)
            # Ensure a plugin name is provided for these actions.
            if [[ -z "$SERVICE" ]]; then
                print_error "Plugin name is required for '$ACTION' action." "Use --plug <plugin_name>." 1
            fi
            
            # Get plugin details and validate. This populates global variables like NAME, NAMESPACE,
            # VALUES_PATH, HELM_INSTALL_CMD, HELM_UPGRADE_CMD, NOTES, DEFAULT_STORAGE_CLASS.
            get_and_validate_plugin_details "$SERVICE"
            
            # Set FULL_LOG_FILE now that $NAME (plugin name) is available. This needs to be set globally.
            # The timestamp ensures unique log files for each operation.
            FULL_LOG_FILE="$LOG_DIR/${NAME}-${ACTION}-$(date +%s).log"

            # Perform the specific action based on the ACTION variable
            case "$ACTION" in
                install)
                    # Validate the Helm command and repository, including a dry-run.
                    validate_helm_command_and_repo
                    # Deploy the plugin using the validated Helm command.
                    deploy_plugin
                    # Run post-deployment health checks specific to the plugin.
                    run_post_checks
                    ;;
                upgrade)
                    # When upgrading, temporarily use the HELM_UPGRADE_CMD for validation and deployment.
                    # Save the original HELM_INSTALL_CMD to restore it later.
                    local original_helm_install_cmd="$HELM_INSTALL_CMD"
                    HELM_INSTALL_CMD="$HELM_UPGRADE_CMD" # Assign upgrade command for subsequent functions
                    validate_helm_command_and_repo # Dry-run with the upgrade command
                    deploy_plugin                  # Deploy using the (now assigned) HELM_INSTALL_CMD (which is HELM_UPGRADE_CMD)
                    run_post_checks
                    HELM_INSTALL_CMD="$original_helm_install_cmd" # Restore original install command
                    ;;
                validate-only)
                    # Only perform validation (dry-run) and report success.
                    validate_helm_command_and_repo
                    print_info "✅ Validation successful for plugin '$NAME'. No changes made."
                    ;;
                uninstall)
                    # Perform the uninstall operation.
                    uninstall_plugin
                    ;;
                *)
                    # Fallback for unhandled specific actions (should ideally not be reached).
                    print_error "Unhandled specific action: $ACTION. This is an internal error." "Please report this bug." 1
                    ;;
            esac
            # Print a summary of the operation.
            print_summary
            ;;

        *)
            # Handle cases where ACTION is not recognized by the main case statement.
            print_error "Invalid or unhandled action: '$ACTION'." "Use 'install', 'upgrade', 'uninstall', 'validate-only', 'edit', 'list', or 'create'. Use --help for usage." 1
            ;;
    esac
}

# Call the main function with all command-line arguments.
main "$@"
