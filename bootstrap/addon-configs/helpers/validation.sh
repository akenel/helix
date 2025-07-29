#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

# 🔧 Helix Plugin Installer – Sherlock Edition
set -euo pipefail
IFS=$'\n\t'

# --- Validate Core Environment ---
validate_env() {
    print_info "🔍 Validating environment..."

    [[ -d "$SCRIPT_DIR" ]] || print_error "Script directory not found: $SCRIPT_DIR" "" 1
    [[ -f "$CONFIG_FILE" ]] || print_error "Config file not found: $CONFIG_FILE." "" 1
    [[ -d "$ROOT_DIR/utils/core" ]] || print_error "Missing utils/core directory." "" 1
    [[ -d "$ROOT_DIR/bootstrap/addon-configs" ]] || print_error "Missing addon-configs directory." "" 1
    mkdir -p "$LOG_DIR" || print_error "Unable to create log directory: $LOG_DIR" "Check write permissions." 1

    for cmd in helm kubectl yq; do
        command -v "$cmd" >/dev/null || print_error "Missing required tool: $cmd" "" 1
    done

    print_success "✅ Environment OK"
}

# --- Helm Schema Validation (Optional) ---
validate_yaml_with_helm_schema() {
    local vals_path="$1"
    if ! command -v helm-schema &>/dev/null; then
        print_info "🧪 helm-schema not installed. Skipping schema validation."
        return
    fi

    print_info "📄 Validating YAML schema for $vals_path..."
    if ! helm-schema lint "$vals_path"; then
        print_error "Schema validation failed for $vals_path" "Check chart documentation or run 'helm-schema lint $vals_path'" 1
    fi
    print_success "✅ YAML schema valid"
}

# --- Extract Plugin Details (Simplified) ---
get_and_validate_plugin_details() {
    local service_name="$1"
    local path=".plugins[] | select(.name==\"$service_name\" and .enabled==true)"

    local plugin_data
    if ! plugin_data=$(yq -e "$path" "$CONFIG_FILE"); then
        print_error "Plugin '$service_name' not found or disabled in $CONFIG_FILE." \
                    "Verify 'enabled: true' and correct name." 1
    fi

    # Simple extraction - service name is used for everything by default
    NAME=$(echo "$plugin_data" | yq -r '.name // ""')
    NAMESPACE=$(echo "$plugin_data" | yq -r '.namespace // ""')
    VALUES_FILE_RAW=$(echo "$plugin_data" | yq -r '.values_file // ""')
    NOTES=$(echo "$plugin_data" | yq -r '.notes // ""')
    DEFAULT_STORAGE_CLASS=$(echo "$plugin_data" | yq -r '.default_storage_class // ""')

    # Use service name as namespace if not specified (simple convention)
    [[ -z "$NAMESPACE" ]] && NAMESPACE="$NAME"

    [[ -z "$NAME" || -z "$VALUES_FILE_RAW" ]] && \
        print_error "Missing required fields: name or values_file in $CONFIG_FILE" "" 1

    VALUES_PATH="$ROOT_DIR/$VALUES_FILE_RAW"
    [[ ! -f "$VALUES_PATH" ]] && print_error "Values file not found: $VALUES_PATH" "" 1

    # Validate YAML syntax
    if ! yq eval '.' "$VALUES_PATH" >/dev/null 2>&1; then
        print_error "Invalid YAML in $VALUES_PATH" "Check indentation and syntax." 1
    fi

    # Simple chart definition - use explicit fields for clean, reliable deployments
    local chart_repo=$(echo "$plugin_data" | yq -r '.helm_chart_repo // ""')
    local chart_name=$(echo "$plugin_data" | yq -r '.helm_chart_name // ""')
    local chart_version=$(echo "$plugin_data" | yq -r '.helm_chart_version // ""')

    # Require explicit chart definition for reliability
    if [[ -z "$chart_repo" || -z "$chart_name" || -z "$chart_version" ]]; then
        print_error "Missing required chart fields for '$NAME'" \
                    "Required: helm_chart_repo, helm_chart_name, helm_chart_version in $CONFIG_FILE" 1
    fi

    print_info "📦 Deploying $NAME: $chart_repo/$chart_name:$chart_version → namespace:$NAMESPACE"

    # Build simple, reliable commands
    CHART_REFERENCE="$chart_repo/$chart_name"
    CHART_VERSION="$chart_version"
    
    # Simple pattern: service_name = release_name = namespace
    HELM_INSTALL_CMD="helm install $NAME $CHART_REFERENCE --version $CHART_VERSION --namespace $NAMESPACE --create-namespace --wait --timeout 5m --atomic"
    HELM_UPGRADE_CMD="helm upgrade $NAME $CHART_REFERENCE --version $CHART_VERSION --namespace $NAMESPACE --wait --timeout 5m --atomic"
    
    print_info "🚀 Install command: $HELM_INSTALL_CMD"
}

# --- Simple Helm Validation ---
validate_helm_command_and_repo() {
    print_info "🛠 Validating Helm repository..."

    # Extract chart repo from the variables set in get_and_validate_plugin_details
    local chart_repo_name="${CHART_REFERENCE%%/*}"  # Get repo name from "portainer/portainer"
    
    # Check if repo exists, add if missing
    if ! helm repo list -o yaml | yq -e ".[] | select(.name==\"$chart_repo_name\")" >/dev/null 2>&1; then
        print_info "📥 Adding Helm repository '$chart_repo_name'..."
        
        # Try to determine repo URL from common patterns
        local repo_url=""
        
        # Common repository URLs for known services
        case "$chart_repo_name" in
            "portainer") repo_url="https://portainer.github.io/k8s/" ;;
            "n8n") repo_url="https://8gears.container-registry.com/chartrepo/library" ;;
            "bitnami") repo_url="https://charts.bitnami.com/bitnami" ;;
            "hashicorp") repo_url="https://helm.releases.hashicorp.com" ;;
            "kong") repo_url="https://charts.konghq.com" ;;
            "minecraft-server-charts") repo_url="https://itzg.github.io/minecraft-server-charts/" ;;
            *) 
                local artifacthub_url=$(yq -r ".plugins[] | select(.name==\"$NAME\").artifacthub_url // \"\"" "$CONFIG_FILE")
                print_error "Unknown repository '$chart_repo_name'" \
                           "Add repo manually: helm repo add $chart_repo_name <URL>\nRefer: $artifacthub_url" 1
                ;;
        esac
        
        if [[ -n "$repo_url" ]]; then
            if helm repo add "$chart_repo_name" "$repo_url"; then
                helm repo update "$chart_repo_name"
                print_success "✅ Added repository '$chart_repo_name'"
            else
                print_error "Failed to add repository '$chart_repo_name'" \
                           "Try manually: helm repo add $chart_repo_name $repo_url" 1
            fi
        fi
    else
        print_success "✅ Repository '$chart_repo_name' available"
        helm repo update "$chart_repo_name" >/dev/null 2>&1 || true
    fi

    # Simple dry-run validation
    print_info "🧪 Testing Helm deployment..."
    local test_cmd="$HELM_INSTALL_CMD -f $VALUES_PATH --dry-run"
    
    if $DEBUG; then
        print_info "🔍 Dry-run: $test_cmd"
        eval "$test_cmd" || print_error "Helm dry-run failed" "Check values file and chart availability" 1
    else
        eval "$test_cmd" >/dev/null 2>&1 || print_error "Helm dry-run failed" "Run with --debug for details" 1
    fi
    
    print_success "✅ Helm validation passed"
}
