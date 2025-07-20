#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

# 🔧 Helix Plugin Installer – Sherlock Edition
set -euo pipefail
IFS=$'\n\t'

# --- Environment Validation ---
# validate_env: Checks for the presence of required commands (helm, kubectl, yq)
# and verifies essential directory structures.
validate_env() {
    print_info "🔍 Validating environment..."

    # Check for critical directory paths.
    [[ -d "$SCRIPT_DIR" ]] || print_error "Script directory not found: $SCRIPT_DIR" "" 1
    [[ -f "$CONFIG_FILE" ]] || print_error "Config file not found: $CONFIG_FILE. Expected at: $CONFIG_FILE" "" 1
    [[ -d "$ROOT_DIR/utils/core" ]] || print_error "Core utilities directory missing: $ROOT_DIR/utils/core" "" 1
    [[ -d "$ROOT_DIR/bootstrap/addon-configs" ]] || print_error "Addon configs directory not found: $ROOT_DIR/bootstrap/addon-configs" "" 1

    # Ensure the log directory exists and is writable.
    mkdir -p "$LOG_DIR" || print_error "Cannot create log directory: $LOG_DIR." "Check permissions." 1

    # Check for required command-line tools.
    for cmd in helm kubectl yq; do
        command -v "$cmd" >/dev/null || print_error "Missing required command: '$cmd'. Please install it." "" 1
    done

    print_success "Environment OK"
}

# --- Schema Validation with helm-schema ---
# validate_yaml_with_helm_schema: Validates a YAML file against a Helm chart's schema
# using the 'helm-schema' tool. Skips if 'helm-schema' is not installed.
# Arguments:
#   $1 - The path to the values file to validate.
validate_yaml_with_helm_schema() {
    local vals_path="$1"
    command -v helm-schema >/dev/null || {
        print_info "🔍 'helm-schema' not installed. Skipping YAML schema validation. (Install with: 'go install github.com/karuppiah7890/helm-schema@latest')"
        return
    }
    print_info "🧪 Validating YAML schema for $vals_path..."
    if ! helm-schema lint "$vals_path"; then
        print_error "Schema validation failed for values file: $vals_path." \
                    "This usually means the values.yaml structure doesn't match the chart's schema.yaml. Check Helm chart documentation." 1
    fi
    print_success "YAML schema valid for $vals_path ✅"
}

# --- Get Plugin Details and Validate Core Fields ---
# get_and_validate_plugin_details: Extracts and validates plugin configuration from services.yaml.
# Populates global variables (NAME, NAMESPACE, VALUES_PATH, HELM_INSTALL_CMD, HELM_UPGRADE_CMD, NOTES, DEFAULT_STORAGE_CLASS).
# Arguments:
#   $1 - The name of the service/plugin to retrieve details for.
get_and_validate_plugin_details() {
    local service_name="$1"
    # yq path to select the enabled plugin entry.
    local path=".plugins[] | select(.name==\"$service_name\" and .enabled==true)"

    local plugin_data # Variable to hold the raw YAML data for the plugin.

    # Attempt to retrieve plugin data. If not found or disabled, print an error and exit.
    if ! plugin_data=$(yq -e "$path" "$CONFIG_FILE"); then
        print_error "Plugin '$service_name' not found or is disabled in '$CONFIG_FILE'." \
                    "Verify the plugin 'name' and 'enabled: true' in '$CONFIG_FILE'.\n"\
                    "You can inspect it with: 'yq '.plugins[] | select(.name==\"$service_name\")' '$CONFIG_FILE'." 1
    fi
    
    # Extract core fields and validate their presence.
    NAME=$(echo "$plugin_data" | yq -r '.name // ""')
    [[ -z "$NAME" ]] && \
        print_error "Field 'name' missing or empty in config for '$service_name'." \
                    "Check the 'name' field for plugin '$service_name' in '$CONFIG_FILE'." 1

    NAMESPACE=$(echo "$plugin_data" | yq -r '.namespace // ""')
    [[ -z "$NAMESPACE" ]] && \
        print_error "Field 'namespace' missing or empty in config for plugin '$NAME'." \
                    "Check the 'namespace' field for plugin '$NAME' in '$CONFIG_FILE'." 1
    # Validate namespace format (alphanumeric, dashes, underscores, no leading/trailing dashes/underscores).
    if ! [[ "$NAMESPACE" =~ ^[a-zA-Z0-9]([a-zA-Z0-9_-]*[a-zA-Z0-9])?$ ]]; then
        print_error "Invalid namespace format: '$NAMESPACE'." \
                    "Namespaces must start with an alphanumeric character, can contain dashes and underscores, "\
                    "and must not end with a dash or underscore. Example: 'my-namespace'." 1
    fi 

    VALUES_FILE_RAW=$(echo "$plugin_data" | yq -r '.values_file // ""')
    [[ -z "$VALUES_FILE_RAW" ]] && \
        print_error "Field 'values_file' missing or empty in config for plugin '$NAME' in '$CONFIG_FILE'." \
                    "Expected a path relative to repository root, e.g., 'bootstrap/addon-configs/$NAME/$NAME-values.yaml'." 1

    # Construct absolute path for values file and verify its existence.
    VALUES_PATH="$ROOT_DIR/$VALUES_FILE_RAW"
    [[ ! -f "$VALUES_PATH" ]] && \
        print_error "Values file not found at expected path: '$VALUES_PATH' for plugin '$NAME'." \
                    "Verify the 'values_file' path in '$CONFIG_FILE' is correct and the file actually exists.\n"\
                    "Check if the file exists: 'ls -l \"$VALUES_PATH\"'." 1
    
    # Validate YAML syntax of the values file.
    if ! yq eval '.' "$VALUES_PATH" >/dev/null 2>&1; then
        print_error "Invalid YAML syntax in values file: '$VALUES_PATH' for plugin '$NAME'." \
                    "Check for indentation errors, missing colons, or invalid YAML. Run: 'yq eval '.' \"$VALUES_PATH\"'." 1
    fi

    # --- NEW: Explicit Chart Definition Fields (Prioritize these if present) ---
    local chart_repo_explicit=$(echo "$plugin_data" | yq -r '.helm_chart_repo // ""')
    local chart_name_explicit=$(echo "$plugin_data" | yq -r '.helm_chart_name // ""')
    local chart_version_explicit=$(echo "$plugin_data" | yq -r '.helm_chart_version // ""')
    local release_name_override_explicit=$(echo "$plugin_data" | yq -r '.helm_release_name_override // ""')

    # Construct HELM_INSTALL_CMD from explicit fields if enough information is present.
    if [[ -n "$chart_name_explicit" && -n "$chart_version_explicit" ]]; then
        print_info "Using explicit Helm chart definition fields for '$NAME'."
        local effective_release_name="${release_name_override_explicit:-$NAME}" # Use override or plugin name
        local effective_chart_ref=""

        if [[ -n "$chart_repo_explicit" ]]; then
            effective_chart_ref="${chart_repo_explicit}/${chart_name_explicit}"
        else
            # If no repo is specified, assume OCI or a local path.
            # For OCI, we expect chart_name_explicit to be the full OCI URL (e.g., "oci://registry.com/repo/chart").
            effective_chart_ref="$chart_name_explicit"
        fi
        
        # Construct the base install command using explicit values, ensuring proper quoting.
        HELM_INSTALL_CMD="helm install \"$effective_release_name\" \"$effective_chart_ref\" --version \"$chart_version_explicit\""
        # The normalize_helm_command function (called next) will ensure --namespace and handle other aspects.
    else
        # Fallback to parsing helm_install_cmd string if explicit fields are missing or incomplete.
        HELM_INSTALL_CMD=$(echo "$plugin_data" | yq -r '.helm_install_cmd // ""')
        [[ -z "$HELM_INSTALL_CMD" ]] && \
            print_error "Field 'helm_install_cmd' missing or empty in config for plugin '$NAME' in '$CONFIG_FILE'." \
                        "This should be the full 'helm install/upgrade' command, e.g., 'helm install <name> <repo>/<chart> --version <ver>', or explicit chart fields must be set." 1
        print_info "Falling back to parsing 'helm_install_cmd' string for '$NAME'."
    fi

    # Normalize the install command (this is still important for ensuring namespace, stripping 'my-' etc.).
    # It will now work with either an explicitly constructed command or a parsed one.
    HELM_INSTALL_CMD=$(normalize_helm_command "$HELM_INSTALL_CMD" "$NAME" "$NAMESPACE" "install")

    HELM_UPGRADE_CMD=$(echo "$plugin_data" | yq -r '.helm_upgrade_cmd // ""')
    # If helm_upgrade_cmd is empty, default it to the normalized install command.
    if [[ -z "$HELM_UPGRADE_CMD" ]]; then
        print_info "Field 'helm_upgrade_cmd' is empty. Defaulting to normalized 'helm_install_cmd'."
        HELM_UPGRADE_CMD="$HELM_INSTALL_CMD" # Use normalized install command
    else
        # Normalize the upgrade command if it was provided.
        HELM_UPGRADE_CMD=$(normalize_helm_command "$HELM_UPGRADE_CMD" "$NAME" "$NAMESPACE" "upgrade")
    fi

    NOTES=$(echo "$plugin_data" | yq -r '.notes // ""') # Get notes, default to empty string if not present.

    # --- NEW: Get default_storage_class ---
    DEFAULT_STORAGE_CLASS=$(echo "$plugin_data" | yq -r '.default_storage_class // ""')
    if [[ -n "$DEFAULT_STORAGE_CLASS" ]]; then
        print_info "Default storage class set for '$NAME': '$DEFAULT_STORAGE_CLASS'."
    fi

    # Run schema validation (if helm-schema is installed).
    validate_yaml_with_helm_schema "$VALUES_PATH"
}

# --- Validate Helm Command and Repo ---
# validate_helm_command_and_repo: Validates the Helm chart's repository and performs a dry-run.
# Relies on the global HELM_INSTALL_CMD (which is already normalized).
validate_helm_command_and_repo() {
    print_info "🛠 Validating Helm command and repository..."
    if [[ -z "$HELM_INSTALL_CMD" ]]; then
    print_warn "No Helm install command defined. Skipping validation."
    return 0
    fi

    local chart_ref # Variable to hold the chart reference (e.g., "repo/chart" or "oci://...")
    # Parse the normalized HELM_INSTALL_CMD to extract the chart reference.
    # The normalized command structure is: helm <cmd_type> <release_name> <chart_ref> [flags...]
    if [[ "$HELM_INSTALL_CMD" =~ ^helm[[:space:]]+(install|upgrade)[[:space:]]+\"[^\"]+\"[[:space:]]+\"([^\"]+)\" ]]; then
        chart_ref="${BASH_REMATCH[2]}" # chart_ref is the 2nd captured group from the quoted chart ref
    else
        print_error "Could not extract chart reference from normalized 'helm_install_cmd': '$HELM_INSTALL_CMD'." \
                    "Internal error during command parsing. Please ensure the normalized command format is correct." 1
    fi

    local repo_name="" # Variable to hold the repository name (if applicable)
    if [[ "$chart_ref" == oci://* ]]; then
        # For OCI charts, the "repo" is part of the OCI URL.
        repo_name=$(echo "$chart_ref" | sed -E 's/oci:\/\/(.*)\/.*/\1/')
        print_info "OCI Chart detected. Registry: $repo_name"
        print_info "Skipping 'helm repo list' check for OCI chart."
    elif [[ "$chart_ref" == */* ]]; then
        # Standard chart repo/chart format (e.g., "bitnami/nginx").
        repo_name="${chart_ref%%/*}" # Extract repo name before the first '/'
        print_info "Standard Helm chart detected. Repository: $repo_name"
        # Check if the Helm repository is added locally.
        if ! helm repo list -o yaml | yq -e ".[] | select(.name==\"$repo_name\")" >/dev/null 2>&1; then
            local artifacthub_url=$(yq -r ".plugins[] | select(.name==\"$SERVICE\" and .enabled==true).artifacthub_url // \"\"" "$CONFIG_FILE")
            print_error "Helm repository '$repo_name' not found in your local Helm configuration." \
                        "🔍 You likely need to run: 'helm repo add $repo_name <REPO_URL>'\n"\
                        "🧠 Tip: Check ArtifactHub or the plugin's 'artifacthub_url' in services.yaml for the correct <REPO_URL>:\n🔗 $artifacthub_url" \
                        1
        else
            print_success "🗂 Helm repo '$repo_name' is available."
        fi
    else
        # Local chart or no explicit repo (e.g., './my-chart' or a chart from the current directory).
        print_info "Helm chart is likely local or uses an implicit repository (e.g., './my-chart')."
    fi

    # Perform Helm dry-run.
    # The HELM_INSTALL_CMD is already normalized. Append values file and debug flag if needed.
    local final_helm_cmd="$HELM_INSTALL_CMD"
    if [[ -n "$VALUES_PATH" && -f "$VALUES_PATH" ]]; then
        final_helm_cmd+=" -f $(realpath "$VALUES_PATH")"
    fi
    final_helm_cmd+=" --dry-run"
    $DEBUG && final_helm_cmd+=" --debug" # Add --debug to dry-run only if DEBUG is on

    print_info "🧪 Running Helm dry-run: $final_helm_cmd"
    # Execute the dry-run command. Redirect output to FULL_LOG_FILE.
    if ! eval "$final_helm_cmd" &> "$FULL_LOG_FILE"; then
        print_error "Helm dry-run failed for plugin '$NAME'." \
                    "This usually indicates a problem with the Helm command, chart, or values file structure.\n"\
                    "Review the output in '$FULL_LOG_FILE' and ensure your 'helm_install_cmd' and 'values.yaml' are correct.\n"\
                    "You can try running the command manually: '$final_helm_cmd'." \
                    1
    fi

    print_success "✅ Helm command and dry-run validated."
}
