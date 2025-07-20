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
SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)" # Assumes script is in <repo_root>/bootstrap/addon-configs

CONFIG_FILE="$ROOT_DIR/bootstrap/addon-configs/services.yaml"
LOG_DIR="$ROOT_DIR/logs"
FULL_LOG_FILE="" # Will be populated in main() after NAME is known

# --- Source Helper Scripts ---
# Source order matters: display functions needed first by others.
source "$SCRIPT_DIR/helpers/display.sh"    # For print_info, print_error, print_success, print_usage, print_summary
source "$ROOT_DIR/utils/core/spinner.sh"   # Your existing spinner (needed by deployment.sh)
source "$SCRIPT_DIR/helpers/parsing.sh"    # For parse_args, normalize_helm_command, run_plugin_wizard
source "$SCRIPT_DIR/helpers/validation.sh" # For validate_env, validate_yaml_with_helm_schema, get_and_validate_plugin_details, validate_helm_command_and_repo
source "$SCRIPT_DIR/helpers/deployment.sh" # For deploy_plugin, uninstall_plugin, run_post_checks

# ... (rest of install-service.sh, including main() function) ...
main() {
    validate_env # No dependency on parsing.sh here
    parse_args "$@"
    case "$ACTION" in
        list)
            print_info "📦 Available Plugins:"
            if yq -r '.plugins[] | select(.enabled==true) | "• \(.name): \(.description)"' "$CONFIG_FILE"; then
                print_success "Plugin listing complete."
            else
                print_error "Failed to list plugins from '$CONFIG_FILE'." "Check YAML syntax or 'plugins' array structure in '$CONFIG_FILE'." 1
            fi
            exit 0
            ;;

        create)
            run_plugin_wizard # This function will handle all prompts and config file updates
            exit 0
            ;;

        edit)
            if [[ -z "$SERVICE" ]]; then
                print_error "Plugin name is required for 'edit' action." "Use --plug <plugin_name>." 1
            fi
            # Get plugin details; this populates NAME, VALUES_PATH etc.
            get_and_validate_plugin_details "$SERVICE"
            print_info "✏️ Editing values file for '$NAME': $(realpath "$VALUES_PATH")"
            "${EDITOR:-nano}" "$(realpath "$VALUES_PATH")" || print_error "Failed to open editor for '$VALUES_PATH'." "Check EDITOR environment variable or permissions." 1
            print_success "Values file edited. Remember to validate changes, possibly with '$0 --plug $NAME --validate-only'."
            exit 0
            ;;

        install|upgrade|validate-only|uninstall)
            if [[ -z "$SERVICE" ]]; then
                print_error "Plugin name is required for '$ACTION' action." "Use --plug <plugin_name>." 1
            fi
            
            # Get plugin details and validate. This populates NAME, NAMESPACE, VALUES_PATH, HELM_INSTALL_CMD, NOTES, DEFAULT_STORAGE_CLASS.
            get_and_validate_plugin_details "$SERVICE"
            
            # Set FULL_LOG_FILE now that $NAME is available. This needs to be set globally.
            FULL_LOG_FILE="$LOG_DIR/${NAME}-${ACTION}-$(date +%s).log"

            case "$ACTION" in
                install)
                    validate_helm_command_and_repo # Performs dry-run, depends on HELM_INSTALL_CMD, VALUES_PATH
                    deploy_plugin                  # Uses HELM_INSTALL_CMD, VALUES_PATH, NAMESPACE, DEFAULT_STORAGE_CLASS
                    run_post_checks                # Uses NAME, NAMESPACE
                    ;;
                upgrade)
                    local original_helm_install_cmd="$HELM_INSTALL_CMD" # Save current install command
                    HELM_INSTALL_CMD="$HELM_UPGRADE_CMD" # Temporarily use upgrade command for deployment functions
                    validate_helm_command_and_repo # Dry-run with upgrade command
                    deploy_plugin                  # Uses the (now assigned) HELM_INSTALL_CMD (which is HELM_UPGRADE_CMD)
                    run_post_checks
                    HELM_INSTALL_CMD="$original_helm_install_cmd" # Restore
                    ;;
                validate-only)
                    validate_helm_command_and_repo
                    print_info "Validation successful for plugin '$NAME'. No changes made."
                    ;;
                uninstall)
                    uninstall_plugin
                    ;;
            esac
            print_summary
            ;;

        *)
            print_error "Invalid or unhandled action: '$ACTION'." "Use 'install', 'upgrade', 'uninstall', 'validate-only', 'edit', 'list', or 'create'. Use --help for usage." 1
            ;;
    esac
}

main "$@"