#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

# 🔧 Helix Plugin Installer – Sherlock Edition
set -euo pipefail
IFS=$'\n\t'

# --- Parse CLI Arguments ---
# parse_args: Parses command-line arguments and sets global variables ACTION, DEBUG, SERVICE.
# Arguments:
#   $@ - All command-line arguments passed to the script.
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --install)
            ACTION="install"
            shift
            ;;
            --upgrade)
            ACTION="upgrade"
            shift
            ;;
            --uninstall)
            ACTION="uninstall"
            shift
            ;;
            --validate-only)
            ACTION="validate-only"
            shift
            ;;
            --edit-config|--edit)
            ACTION="edit"
            shift
            ;;
            --list)
            ACTION="list"
            shift
            ;;
            --create)
            ACTION="create"
            shift
            ;;
            --get-info)
            ACTION="get-info"
            shift
            ;;
            --plug)
                # Ensure --plug is followed by a value and not another flag.
                if [[ -z "$2" || "$2" =~ ^-- ]]; then
                    print_error "--plug requires a plugin name." "Example: --plug my-plugin" 1
                fi
                SERVICE="$2"; shift # Set SERVICE global and consume the argument.
                ;;
            --debug) 
                export DEBUG=true
                echo "🐛 DEBUG MODE ENABLED" >&2
                ;; # Enable debug mode and export for child scripts.
            --help) print_usage; exit 0 ;; # Display usage and exit.
            *) print_error "Unknown option: $1" "Run with --help for usage." 1 ;; # Handle unknown options.
        esac
        shift # Move to the next argument.
    done

    # Handle implicit actions if no action flag is provided explicitly.
    # If a service is specified but no action, default to 'install'.
    if [[ -z "$ACTION" && -n "$SERVICE" ]]; then
        ACTION="install"
    # If neither action nor service is specified, display usage and exit.
    elif [[ -z "$ACTION" ]]; then
        print_usage # Force showing usage if no action or service provided.
        exit 1 # Should not be reached due to print_usage exit, but for safety.
    fi
}

# --- Normalize Helm Command ---
# normalize_helm_command: Ensures common flags and release naming conventions are applied.
# This function is designed to take a potentially "raw" Helm command string (e.g., copied from Artifact Hub)
# and normalize it to fit Helix's conventions (correct release name, namespace).
# Arguments:
#   $1 - The raw Helm command string.
#   $2 - The expected plugin name (from services.yaml .name).
#   $3 - The expected namespace (from services.yaml .namespace).
#   $4 - The command type ("install" or "upgrade").
# Returns: The normalized command string via stdout.
normalize_helm_command() {
    local raw_cmd="$1"
    local expected_name="$2"      # e.g., 'portainer' (from .name)
    local expected_namespace="$3" # e.g., 'portainer' (from .namespace)
    local cmd_type="$4"           # 'install' or 'upgrade'
    
    # Ensure the command type is valid
    if [[ "$cmd_type" != "install" && "$cmd_type" != "upgrade" ]]; then
        print_error "Invalid command type: '$cmd_type'. Must be 'install' or 'upgrade'." "Check the command type passed to normalize_helm_command." 1   
    fi
    # Ensure the expected name and namespace are provided
    if [[ -z "$expected_name" || -z "$expected_namespace" ]]; then
        print_error "Expected name and namespace must be provided for Helm command normalization." \
                    "Check the arguments passed to normalize_helm_command." 1   
    fi
    # Ensure the raw command is not empty
    if [[ -z "$raw_cmd" ]]; then
        print_error "Raw Helm command cannot be empty." "Provide a valid Helm command string." 1
    fi
    # Basic validation - ensure command starts with helm
    if [[ ! "$raw_cmd" =~ ^helm ]]; then
        print_error "Invalid Helm command format: '$raw_cmd'." "Command must start with 'helm'." 1
    fi
    
    # Debug info
    $DEBUG && print_info "⚙️ Normalizing Helm $cmd_type command: '$raw_cmd'"
    $DEBUG && print_info "📋 Raw command length: ${#raw_cmd} characters"
    
    # Convert the command string into an array of arguments for easier processing.
    local -a cmd_args
    read -r -a cmd_args <<< "$raw_cmd"
    
    $DEBUG && print_info "📊 Command parsed into ${#cmd_args[@]} arguments: ${cmd_args[*]}"

    local current_arg_index=0
    local parsed_action=""
    local parsed_release_name=""
    local parsed_chart_ref=""
    local parsed_version_flag=""
    local has_explicit_namespace=false

    # Parse the initial fixed parts of the Helm command: helm <action> <release_name> <chart_ref>
    if [[ ${#cmd_args[@]} -gt 0 && "${cmd_args[0]}" == "helm" ]]; then
        current_arg_index=1 # Start after "helm"
    else
        print_error "Invalid Helm command format: '$raw_cmd'." "Command must start with 'helm'." 1
    fi

    if [[ ${#cmd_args[@]} -gt $current_arg_index && ("${cmd_args[$current_arg_index]}" == "install" || "${cmd_args[$current_arg_index]}" == "upgrade") ]]; then
        parsed_action="${cmd_args[$current_arg_index]}"
        current_arg_index=$((current_arg_index + 1))
    else
        print_error "Invalid Helm command format: '$raw_cmd'." "Command must specify 'install' or 'upgrade' action." 1
    fi

    if [[ ${#cmd_args[@]} -gt $current_arg_index && -n "${cmd_args[$current_arg_index]}" ]]; then
        parsed_release_name="${cmd_args[$current_arg_index]}"
        current_arg_index=$((current_arg_index + 1))
    else
        print_error "Invalid Helm command format: '$raw_cmd'." "Release name is missing." 1
    fi

    if [[ ${#cmd_args[@]} -gt $current_arg_index && -n "${cmd_args[$current_arg_index]}" ]]; then
        parsed_chart_ref="${cmd_args[$current_arg_index]}"
        current_arg_index=$((current_arg_index + 1))
    else
        print_error "Invalid Helm command format: '$raw_cmd'." "Chart reference is missing." 1
    fi

    # --- Normalize Release Name ---
    local effective_release_name="$parsed_release_name"
    if [[ "$parsed_release_name" == "my-$expected_name" ]]; then
        $DEBUG && print_info "🔧 Stripping 'my-' prefix from release name '$parsed_release_name'. Using '$expected_name'."
        effective_release_name="$expected_name"
    elif [[ "$parsed_release_name" != "$expected_name" ]]; then
        $DEBUG && print_info "🔧 Helm release name '$parsed_release_name' in config does not match expected plugin name '$expected_name'. Forcing to '$expected_name'."
        effective_release_name="$expected_name"
    fi

    # Start building the final command
    local final_cmd="helm $cmd_type $effective_release_name $parsed_chart_ref"

    # Process remaining arguments (flags) with safe array access
    for (( i=current_arg_index; i<${#cmd_args[@]}; i++ )); do
        local arg="${cmd_args[$i]}"
        local next_arg=""
        
        # Safely get next argument if it exists
        if [[ $((i+1)) -lt ${#cmd_args[@]} ]]; then
            next_arg="${cmd_args[$((i+1))]}"
        fi

        if [[ "$arg" == "--namespace" ]]; then
            has_explicit_namespace=true
            i=$((i+1)) # Skip the next argument (the namespace value)
            $DEBUG && print_info "🗑️ Removed existing '--namespace ${cmd_args[$i]}' from command."
        elif [[ "$arg" == "--version" ]]; then
            if [[ -n "$next_arg" ]]; then
                parsed_version_flag="$arg $next_arg" # Capture flag and its value
                i=$((i+1)) # Skip the next argument (the version value)
            else
                parsed_version_flag="$arg" # Just the flag if no value
            fi
        else
            # Add all other arguments as they are
            final_cmd+=" $arg"
        fi
    done

    # Add version flag if it was found
    if [[ -n "$parsed_version_flag" ]]; then
        final_cmd+=" $parsed_version_flag"
    fi

    # Always add our desired namespace flag
    final_cmd+=" --namespace $expected_namespace"

    # Remove any double spaces that might result from concatenations
    final_cmd=$(echo "$final_cmd" | tr -s ' ')
    echo "$final_cmd"
}

# --- Wizard for Adding Plugin Entry ---
# run_plugin_wizard: Guides the user through creating a new plugin entry in services.yaml.
# Prompts for all necessary fields, including new explicit chart definition fields and default storage class.
run_plugin_wizard() {
    print_info "🔧 Starting new plugin wizard..."
    read -rp "Plugin name (e.g., vault): " name
    [[ -z "$name" ]] && print_error "Plugin name cannot be empty." "" 1
    # Check if plugin already exists in the config file.
    if yq -e ".plugins[] | select(.name==\"$name\")" "$CONFIG_FILE" >/dev/null 2>&1; then
        print_error "Plugin '$name' already exists in '$CONFIG_FILE'." "Choose a unique name or edit the existing entry." 1
    fi

    read -rp "Emoji (e.g., 🔐): " emoji
    read -rp "Description: " description
    read -rp "Namespace (e.g., vault): " namespace
    [[ -z "$namespace" ]] && print_error "Namespace cannot be empty." "" 1

    # --- NEW WIZARD PROMPTS FOR EXPLICIT FIELDS ---
    print_info "\n--- Helm Chart Definition ---"
    print_info "💡 You can provide explicit chart details OR a full 'helm install' command."
    print_info "   Explicit fields are preferred for clarity and robustness."
    read -rp "Helm Chart Repository (e.g., 'portainer' for 'portainer/portainer' or leave empty for OCI/local): " helm_chart_repo
    read -rp "Helm Chart Name (e.g., 'portainer' for 'portainer/portainer', or full OCI URL like 'oci://registry.com/repo/n8n'): " helm_chart_name
    read -rp "Helm Chart Version (e.g., '1.0.69'): " helm_chart_version
    read -rp "Helm Release Name Override (optional, if different from plugin name, e.g., 'my-portainer'): " helm_release_name_override
    
    local helm_install_cmd_prompt=""
    # If explicit chart name or version are missing, prompt for the full command string as a fallback.
    if [[ -z "$helm_chart_name" || -z "$helm_chart_version" ]]; then
        print_info "\n--- Fallback to Helm Install Command String ---"
        print_info "💡 Since explicit chart name/version were not provided, we will rely on parsing this string."
        print_info "   Example for n8n: 'helm install my-n8n oci://8gears.container-registry.com/library/n8n --version 1.0.10'"
        read -rp "Full Helm install command string (e.g., 'helm install <name> <repo>/<chart> --version <ver>'): " helm_install_cmd_prompt
        [[ -z "$helm_install_cmd_prompt" ]] && print_error "Helm install command cannot be empty if explicit fields are missing." "" 1
    else
        helm_install_cmd_prompt="GENERATED_FROM_EXPLICIT_FIELDS" # Placeholder, actual generation is in validation.sh
        print_info "Helm command will be generated from explicit fields."
    fi

    # --- NEW WIZARD PROMPT FOR DEFAULT STORAGE CLASS ---
    print_info "\n--- Storage Class Configuration ---"
    print_info "💡 If your chart uses persistence and its 'values.yaml' leaves 'persistence.storageClass' empty,"
    print_info "   this default will be injected. Leave empty to disable."
    read -rp "Default Storage Class Name (e.g., 'local-path', 'longhorn'): " default_storage_class

    read -rp "ArtifactHub URL (optional, e.g., https://artifacthub.io/packages/helm/n8n/n8n): " url

    # Suggest default values file path
    local default_values_path="bootstrap/addon-configs/${name}/${name}-values.yaml"
    read -rp "Values file path (relative to repo root, default: $default_values_path): " val_input
    local values_file_path="${val_input:-$default_values_path}"

    # Ensure values directory exists
    local values_dir=$(dirname "$ROOT_DIR/$values_file_path")
    mkdir -p "$values_dir" || print_error "Failed to create values directory: $values_dir" "Check permissions for '$values_dir'." 1
    # Create an empty values file if it doesn't exist
    [[ -f "$ROOT_DIR/$values_file_path" ]] || touch "$ROOT_DIR/$values_file_path" && print_info "Created empty values file: $ROOT_DIR/$values_file_path"

    # Display a preview of the YAML block to be added to services.yaml
    cat <<EOF

📝 Preview YAML block to be added to $CONFIG_FILE:
  - name: $name
    emoji: ${emoji:-''}
    description: "$description"
    enabled: true
    namespace: $namespace
    values_file: $values_file_path
    artifacthub_url: ${url:-''}
    helm_install_cmd: "$helm_install_cmd_prompt"
EOF
    # Only add explicit fields to the preview if they were provided by the user.
    # Using /dev/stderr to print these so they don't interfere with the 'cat <<EOF' buffer.
    if [[ -n "$helm_chart_repo" ]]; then echo "    helm_chart_repo: \"$helm_chart_repo\""; fi >> /dev/stderr
    if [[ -n "$helm_chart_name" ]]; then echo "    helm_chart_name: \"$helm_chart_name\""; fi >> /dev/stderr
    if [[ -n "$helm_chart_version" ]]; then echo "    helm_chart_version: \"$helm_chart_version\""; fi >> /dev/stderr
    if [[ -n "$helm_release_name_override" ]]; then echo "    helm_release_name_override: \"$helm_release_name_override\""; fi >> /dev/stderr
    if [[ -n "$default_storage_class" ]]; then echo "    default_storage_class: \"$default_storage_class\""; fi >> /dev/stderr

    echo "" >> /dev/stderr # Newline for readability in preview

    read -rp "Append this to services.yaml? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "❌ Cancelled wizard."; return; }

    # Append the new plugin entry to the CONFIG_FILE.
    # Ensure correct indentation for a top-level list item.
    {
      echo "" # Newline for separation
      echo "  - name: $name"
      echo "    emoji: ${emoji:-''}"
      echo "    description: \"$description\""
      echo "    enabled: true"
      echo "    namespace: $namespace"
      echo "    values_file: $values_file_path"
      echo "    artifacthub_url: ${url:-''}"
      echo "    helm_install_cmd: \"$helm_install_cmd_prompt\"" # This will store the "GENERATED..." placeholder if explicit fields were used
      if [[ -n "$helm_chart_repo" ]]; then echo "    helm_chart_repo: \"$helm_chart_repo\""; fi
      if [[ -n "$helm_chart_name" ]]; then echo "    helm_chart_name: \"$helm_chart_name\""; fi
      if [[ -n "$helm_chart_version" ]]; then echo "    helm_chart_version: \"$helm_chart_version\""; fi
      if [[ -n "$helm_release_name_override" ]]; then echo "    helm_release_name_override: \"$helm_release_name_override\""; fi
      if [[ -n "$default_storage_class" ]]; then echo "    default_storage_class: \"$default_storage_class\""; fi
    } >> "$CONFIG_FILE"

    # Try to sort the services.yaml plugins for cleaner config.
    print_info "Attempting to sort plugins in $CONFIG_FILE..."
    if yq -i '.plugins |= sort_by(.name)' "$CONFIG_FILE" 2>/dev/null; then
        print_success "Plugins sorted in $CONFIG_FILE."
    else
        print_info "Could not sort plugins in $CONFIG_FILE. Manual sorting may be needed."
    fi

    print_success "Plugin '$name' added to $CONFIG_FILE"
}
