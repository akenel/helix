# bootstrap/addon-configs/helpers/deployment.sh

#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

# 🔧 Helix Plugin Installer – Sherlock Edition
set -euo pipefail
IFS=$'\n\t'

# --- Plugin Deployment ---
# deploy_plugin: Deploys a Helm chart based on the plugin configuration.
# Handles namespace creation, default storage class injection, and logging.
# Relies on global variables: NAME, NAMESPACE, HELM_INSTALL_CMD, VALUES_PATH, DEFAULT_STORAGE_CLASS, FULL_LOG_FILE, DEBUG, ACTION.
deploy_plugin() {
    print_info "🚀 Deploying plugin: $NAME (Namespace: $NAMESPACE)"
    # FULL_LOG_FILE is already set in main() before calling deploy_plugin.

    local final_helm_cmd="$HELM_INSTALL_CMD" # Start with the already normalized Helm command.
    local temp_values_file="" # Variable to store the path to a temporary values file if created.

    # --- Handle default_storage_class injection ---
    # This logic applies if DEFAULT_STORAGE_CLASS is defined in services.yaml AND
    # the plugin's values file exists.
    if [[ -n "$DEFAULT_STORAGE_CLASS" && -f "$VALUES_PATH" ]]; then
        # Check if persistence is enabled and storageClass is explicitly empty in the original values file.
        local persistence_enabled=$(yq -r '.persistence.enabled // "false"' "$VALUES_PATH")
        local storage_class_set=$(yq -r '.persistence.storageClass // ""' "$VALUES_PATH")

        if [[ "$persistence_enabled" == "true" && -z "$storage_class_set" ]]; then
            print_info "Detected empty persistence.storageClass in '$VALUES_PATH'. Injecting default: '$DEFAULT_STORAGE_CLASS'."
            # Create a temporary copy of the values file.
            temp_values_file=$(mktemp "$LOG_DIR/${NAME}-values-temp-XXXX.yaml")
            cp "$VALUES_PATH" "$temp_values_file"
            
            # Use yq to set the storageClass in the temporary file.
            if ! yq -i ".persistence.storageClass = \"$DEFAULT_STORAGE_CLASS\"" "$temp_values_file"; then
                print_error "Failed to inject default_storage_class '$DEFAULT_STORAGE_CLASS' into temporary values file '$temp_values_file'." \
                            "Check YAML path for persistence.storageClass in $VALUES_PATH." 1
            fi
            # Use the temporary file for the Helm command.
            final_helm_cmd+=" -f $(realpath "$temp_values_file")"
        elif [[ "$persistence_enabled" == "true" && -n "$storage_class_set" ]]; then
            print_info "Persistence is enabled and storageClass is explicitly set to '$storage_class_set' in '$VALUES_PATH'. Default '$DEFAULT_STORAGE_CLASS' will not be applied."
            # If explicitly set, proceed with the original values file.
            final_helm_cmd+=" -f $(realpath "$VALUES_PATH")"
        else
            print_info "Persistence is not enabled or not configured in '$VALUES_PATH'. Default '$DEFAULT_STORAGE_CLASS' will not be applied."
            # If persistence is not enabled or not applicable, just use the original values file if it exists.
            if [[ -f "$VALUES_PATH" ]]; then
                final_helm_cmd+=" -f $(realpath "$VALUES_PATH")"
            fi
        fi
    elif [[ -f "$VALUES_PATH" ]]; then
        # If no default_storage_class is defined or values file doesn't exist, use the original values file if it exists.
        final_helm_cmd+=" -f $(realpath "$VALUES_PATH")"
    fi
    # --- END Handle default_storage_class injection ---

    # Ensure the target namespace exists before running the Helm command.
    # This avoids relying solely on Helm's --create-namespace (which might not always be desired or work).
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_info "Creating namespace '$NAMESPACE' before Helm deployment..."
        kubectl create namespace "$NAMESPACE" || print_error "Failed to create namespace '$NAMESPACE'." "Check permissions or if namespace already exists in a bad state." 1
        print_success "Namespace '$NAMESPACE' created."
    fi

    # Add --atomic flag for install/upgrade actions if DEBUG mode is enabled.
    if [[ ("$ACTION" == "install" || "$ACTION" == "upgrade") ]]; then
        $DEBUG && final_helm_cmd+=" --atomic"
    fi

    print_info "📣 Executing Helm: $final_helm_cmd"

    # Execute the Helm command and capture its output to the log file.
    if "$DEBUG"; then
        # In debug mode, output to console in real-time and also append to log file.
        echo "$final_helm_cmd" | tee -a "$FULL_LOG_FILE" # Echo the command itself to the log
        eval "$final_helm_cmd" | tee -a "$FULL_LOG_FILE" || \
            print_error "Helm deployment failed for '$NAME'." "Check debug output above and full log file: '$FULL_LOG_FILE'." 1
    else
        # In non-debug mode, run with a spinner for visual feedback.
        eval "$final_helm_cmd" &> "$FULL_LOG_FILE" & PID=$!
        spin "$PID" || true # The spin function provides visual feedback and waits for PID.
        wait "$PID" || \
            print_error "Helm deployment failed for '$NAME'." "Check log for details: '$FULL_LOG_FILE'. You might need to manually run the command." 1
    fi

    print_success "Plugin '$NAME' deployed successfully."

    # --- Cleanup temporary values file if created ---
    if [[ -n "$temp_values_file" && -f "$temp_values_file" ]]; then
        print_info "Cleaning up temporary values file: $temp_values_file"
        rm -f "$temp_values_file"
    fi
}

# --- Uninstall Plugin ---
# uninstall_plugin: Uninstalls a Helm release.
# Relies on global variables: NAME, NAMESPACE, FULL_LOG_FILE, DEBUG.
uninstall_plugin() {
    # Ensure plugin name and namespace are set.
    [[ -z "$NAME" || -z "$NAMESPACE" ]] && print_error "Plugin name or namespace not set. Cannot uninstall." "" 1

    print_info "🗑️  Uninstalling plugin: '$NAME' from namespace '$NAMESPACE'..."
    # FULL_LOG_FILE is already set in main() before calling uninstall_plugin.

    # Check if the Helm release exists before attempting to uninstall.
    if ! helm get release "$NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
        print_info "Plugin '$NAME' not found in namespace '$NAMESPACE'. Skipping uninstall."
        print_success "Uninstall for '$NAME' completed (already absent)."
        return 0 # Indicate success for this step (skipped).
    fi

    local uninstall_cmd="helm uninstall '$NAME' --namespace '$NAMESPACE'"
    print_info "📣 Executing: $uninstall_cmd"

    # Execute the uninstall command and capture its output.
    if "$DEBUG"; then
        echo "$uninstall_cmd" | tee -a "$FULL_LOG_FILE" # Echo command to log as well
        eval "$uninstall_cmd" | tee -a "$FULL_LOG_FILE" || \
            print_error "Helm uninstall failed for '$NAME'." "Check debug output above and full log file: '$FULL_LOG_FILE'." 1
    else
        eval "$uninstall_cmd" &> "$FULL_LOG_FILE" & PID=$!
        spin "$PID" || true
        wait "$PID" || \
            print_error "Helm uninstall failed for '$NAME'." "Check log for details: '$FULL_LOG_FILE'. You might need to manually run the command." 1
    fi
    print_success "Plugin '$NAME' uninstalled successfully."
}

# --- Post-Deployment Health Check ---
# run_post_checks: Performs specific health checks after a plugin deployment.
# This function can be extended with checks tailored to each plugin.
# Relies on global variables: NAME, NAMESPACE, FULL_LOG_FILE.
run_post_checks() {
    print_info "🔍 Running post-deployment health checks for '$NAME'..."
        for kind in pods svc ingress; do
            if ! kubectl get "$kind" -n "$NAMESPACE" &>/dev/null; then
            print_error "No $kind found in namespace '$NAMESPACE'. Deployment may have failed."
            fi
        done
    print_success "Post-deployment checks completed for '$NAME'."
}
