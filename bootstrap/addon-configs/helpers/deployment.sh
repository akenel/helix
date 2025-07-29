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
    # We'll use Helm's --create-namespace flag, but also check manually for better error handling.
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_info "🏗️ Namespace '$NAMESPACE' will be created by Helm with --create-namespace flag."
    else
        print_info "✅ Namespace '$NAMESPACE' already exists."
    fi

    # Add essential production-ready flags for reliable deployment
    local helm_flags=""
    
    # Always add --create-namespace to handle namespace creation automatically
    helm_flags+=" --create-namespace"
    
    # Add timeout for reliability (5 minutes default)
    helm_flags+=" --timeout 5m"
    
    # Add wait flag to ensure resources are ready before completing
    helm_flags+=" --wait"
    
    # Add atomic flag for rollback on failure (always recommended)
    helm_flags+=" --atomic"
    
    # Add debug flag in debug mode for detailed output
    if $DEBUG; then
        helm_flags+=" --debug"
    fi
    
    # Append the production flags to the final command
    final_helm_cmd+="$helm_flags"

    print_info "� Executing Helm deployment: $final_helm_cmd"
    print_info "⏳ This may take a few minutes with --wait and --atomic flags..."

    # Execute the Helm command and capture its output to the log file.
    local helm_exit_code=0
    if "$DEBUG"; then
        # In debug mode, output to console in real-time and also append to log file.
        echo "$final_helm_cmd" | tee -a "$FULL_LOG_FILE" # Echo the command itself to the log
        eval "$final_helm_cmd" | tee -a "$FULL_LOG_FILE"
        helm_exit_code=$?
    else
        # In non-debug mode, run with a beautiful braille spinner for visual feedback.
        print_info "🎯 Deploying $NAME with production-ready settings..."
        eval "$final_helm_cmd" &> "$FULL_LOG_FILE" & PID=$!
        
        # Beautiful braille spinner while waiting for deployment
        local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        local delay=0.1
        local temp_msg="🔄 Installing $NAME (namespace: $NAMESPACE, timeout: 5m, atomic rollback enabled)"
        
        # Hide cursor for clean spinner
        tput civis 2>/dev/null || true
        
        while kill -0 "$PID" 2>/dev/null; do
            for (( i=0; i<${#spinner_chars}; i++ )); do
                if ! kill -0 "$PID" 2>/dev/null; then break; fi
                # Clear entire line, print spinner message, move cursor back
                printf "\r\033[K%s %s" "${spinner_chars:$i:1}" "$temp_msg"
                sleep "$delay"
            done
        done
        
        # Clear the spinner line completely and restore cursor
        printf "\r\033[K"
        tput cnorm 2>/dev/null || true
        
        wait "$PID"
        helm_exit_code=$?
    fi

    # Check if deployment actually succeeded by looking at Helm release status
    if [[ $helm_exit_code -ne 0 ]]; then
        # Check if the release was actually created successfully despite exit code
        if helm list -n "$NAMESPACE" | grep -q "$NAME"; then
            print_info "⚠️ Helm command returned non-zero exit code ($helm_exit_code) but release '$NAME' exists. Checking status..."
            local release_status=$(helm status "$NAME" -n "$NAMESPACE" -o json 2>/dev/null | jq -r '.info.status // "unknown"' 2>/dev/null || echo "unknown")
            if [[ "$release_status" == "deployed" ]]; then
                print_success "✅ Despite exit code, Helm release '$NAME' is deployed successfully (status: $release_status)"
            else
                print_error "Helm deployment failed for '$NAME'. Release status: $release_status" "Check debug output above and full log file: '$FULL_LOG_FILE'." 1
            fi
        else
            print_error "Helm deployment failed for '$NAME'. Exit code: $helm_exit_code" "Check debug output above and full log file: '$FULL_LOG_FILE'." 1
        fi
    else
        print_success "🎉 Plugin '$NAME' deployed successfully!"
        print_info "📍 Namespace: $NAMESPACE"
        print_info "⏱️ Deployment completed with --wait (all resources ready)"
        print_info "🛡️ Atomic deployment (automatic rollback on failure)"
        
        # Show quick access commands
        print_info "💡 Quick commands to check status:"
        print_info "   kubectl get all -n $NAMESPACE"
        print_info "   helm status $NAME -n $NAMESPACE"
    fi

    # --- Cleanup temporary values file if created ---
    if [[ -n "$temp_values_file" && -f "$temp_values_file" ]]; then
        print_info "Cleaning up temporary values file: $temp_values_file"
        rm -f "$temp_values_file"
    fi
    
    # --- Pause to show results ---
    print_info ""
    print_info "🎯 Deployment complete! Press Enter to continue or Ctrl+C to exit..."
    read -r
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
    
    # --- Pause to show results ---
    print_info ""
    print_info "🎯 Uninstall complete! Press Enter to continue or Ctrl+C to exit..."
    read -r
}

# --- Post-Deployment Health Check ---
# run_post_checks: Performs specific health checks after a plugin deployment.
# This function can be extended with checks tailored to each plugin.
# Relies on global variables: NAME, NAMESPACE, FULL_LOG_FILE.
run_post_checks() {
    print_info "🔍 Running post-deployment health checks for '$NAME'..."
    
    # Check pods status
    local pod_count=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$NAME" --no-headers 2>/dev/null | wc -l)
    if [[ $pod_count -gt 0 ]]; then
        print_success "✅ Found $pod_count pod(s) for $NAME"
        kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$NAME"
    else
        print_info "ℹ️ No pods found with label app.kubernetes.io/name=$NAME, checking all pods in namespace..."
        kubectl get pods -n "$NAMESPACE" 2>/dev/null || print_info "No pods found in namespace $NAMESPACE"
    fi
    
    # Check services
    local svc_count=$(kubectl get svc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [[ $svc_count -gt 0 ]]; then
        print_success "✅ Found $svc_count service(s) in namespace $NAMESPACE"
        kubectl get svc -n "$NAMESPACE"
    else
        print_info "ℹ️ No services found in namespace $NAMESPACE"
    fi
    
    # Check for NodePort services (common for UI applications)
    local nodeport_services=$(kubectl get svc -n "$NAMESPACE" -o jsonpath='{.items[?(@.spec.type=="NodePort")].metadata.name}' 2>/dev/null)
    if [[ -n "$nodeport_services" ]]; then
        print_info "🌐 NodePort services found: $nodeport_services"
        for svc in $nodeport_services; do
            local nodeport=$(kubectl get svc "$svc" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
            if [[ -n "$nodeport" ]]; then
                print_info "   🔗 Access $svc at: http://localhost:$nodeport"
            fi
        done
    fi
    
    # Call plugin-specific ingress setup if function exists
    if declare -f "setup_ingress_for_${NAME}" >/dev/null; then
        print_info "🌐 Setting up Ingress for $NAME..."
        "setup_ingress_for_${NAME}"
    fi
    
    print_success "🏁 Post-deployment checks completed for '$NAME'."
    
    # --- Pause to show post-deployment results ---
    print_info ""
    print_info "🎯 Post-deployment checks complete! Press Enter to continue or Ctrl+C to exit..."
    read -r
}

# --- Ingress Management ---
# create_standard_ingress: Creates a standard Kubernetes Ingress resource
# This replaces Traefik-specific IngressRoute with portable Kubernetes Ingress
create_standard_ingress() {
    local service_name="$1"
    local service_port="$2"
    local hostname="$3"
    local tls_secret_name="${4:-helix-tls-cert}"
    local additional_annotations="${5:-}"
    
    [[ -z "$service_name" || -z "$service_port" || -z "$hostname" ]] && {
        print_error "create_standard_ingress requires: service_name, service_port, hostname" "" 1
    }
    
    print_info "🌐 Creating standard Kubernetes Ingress for $hostname → $service_name:$service_port"
    
    # Create the Ingress YAML
    local ingress_yaml=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${NAME}-ingress
  namespace: ${NAMESPACE}
  annotations:
    # Standard annotations that work with multiple ingress controllers
    kubernetes.io/ingress.class: "traefik"
    
    # Force HTTPS redirect
    traefik.ingress.kubernetes.io/redirect-entry-point: "https"
    traefik.ingress.kubernetes.io/redirect-permanent: "true"
    
    # TLS configuration
    traefik.ingress.kubernetes.io/router.entrypoints: "websecure"
    traefik.ingress.kubernetes.io/router.tls: "true"
    
    # Security headers
    traefik.ingress.kubernetes.io/router.middlewares: "default-security-headers@kubernetescrd"
    
    # Certificate resolver (if using cert-manager with Traefik)
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    
    ${additional_annotations}
spec:
  tls:
  - hosts:
    - ${hostname}
    secretName: ${tls_secret_name}
  rules:
  - host: ${hostname}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${service_name}
            port:
              number: ${service_port}
EOF
)
    
    # Apply the Ingress
    echo "$ingress_yaml" | kubectl apply -f - || {
        print_error "Failed to create Ingress for $NAME" "Check kubectl permissions and ingress controller status" 1
    }
    
    print_success "✅ Ingress created for $hostname"
    print_info "🔗 Service will be available at: https://$hostname"
    
    # Wait for ingress to be ready
    print_info "⏳ Waiting for Ingress to be ready..."
    kubectl wait --for=condition=ready ingress "${NAME}-ingress" -n "$NAMESPACE" --timeout=60s || {
        print_info "⚠️ Ingress may take longer to be ready. Check with: kubectl get ingress -n $NAMESPACE"
    }
}

# --- Plugin-Specific Ingress Functions ---
# These functions are called automatically if they exist for a plugin

setup_ingress_for_portainer() {
    print_info "🐳 Setting up Portainer Ingress with Keycloak integration..."
    
    # Register OIDC client in Keycloak first
    register_oidc_client "portainer-oidc" "https://portainer.helix/*" "Portainer Container Management Platform"
    
    # Create standard Kubernetes Ingress instead of IngressRoute
    create_standard_ingress "portainer" "9000" "portainer.helix" "helix-tls-cert" \
        "# Portainer-specific annotations
    traefik.ingress.kubernetes.io/router.middlewares: \"${NAMESPACE}-portainer-oidc@kubernetescrd\""
    
    # Create OIDC middleware for Keycloak integration
    setup_portainer_oidc_middleware
    
    print_success "🎉 Portainer Ingress configured with HTTPS and Keycloak OIDC!"
    print_info "🔐 Access: https://portainer.helix (redirects to Keycloak for auth)"
    print_info "💡 Admin credentials are stored in Vault if needed"
    print_info "🔑 OIDC Client ID: portainer-oidc"
}

setup_portainer_oidc_middleware() {
    print_info "🔐 Creating security headers middleware for Portainer..."
    
    # Note: For Portainer OIDC, we don't use ForwardAuth middleware
    # Instead, Portainer handles OIDC directly with its built-in support
    # We just need security headers and proper TLS handling
    
    local middleware_yaml=$(cat <<EOF
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: portainer-oidc
  namespace: ${NAMESPACE}
spec:
  headers:
    customRequestHeaders:
      X-Forwarded-Proto: "https"
      X-Forwarded-Host: "portainer.helix"
    customResponseHeaders:
      X-Frame-Options: "SAMEORIGIN"
      X-Content-Type-Options: "nosniff"
      X-XSS-Protection: "1; mode=block"
      Strict-Transport-Security: "max-age=31536000; includeSubDomains"
      Referrer-Policy: "strict-origin-when-cross-origin"
      Content-Security-Policy: "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'"
---
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: security-headers
  namespace: default
spec:
  headers:
    customRequestHeaders:
      X-Forwarded-Proto: "https"
    customResponseHeaders:
      X-Frame-Options: "SAMEORIGIN"
      X-Content-Type-Options: "nosniff"
      X-XSS-Protection: "1; mode=block"
      Strict-Transport-Security: "max-age=31536000; includeSubDomains"
      Referrer-Policy: "strict-origin-when-cross-origin"
EOF
)
    
    echo "$middleware_yaml" | kubectl apply -f - || {
        print_error "Failed to create security middleware for Portainer" "Check Traefik CRDs are installed" 1
    }
    
    # Create Portainer OIDC configuration
    create_portainer_oidc_config
    
    print_success "✅ Security middleware configured for Portainer"
}

create_portainer_oidc_config() {
    print_info "⚙️ Creating Portainer OIDC configuration..."
    
    # Create a ConfigMap with Portainer OIDC settings
    local oidc_config=$(cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: portainer-oidc-config
  namespace: ${NAMESPACE}
data:
  oidc-settings.json: |
    {
      "OAuthSettings": {
        "ClientID": "portainer-oidc",
        "AuthorizationURI": "https://keycloak.helix/realms/helix/protocol/openid-connect/auth",
        "AccessTokenURI": "https://keycloak.helix/realms/helix/protocol/openid-connect/token",
        "ResourceURI": "https://keycloak.helix/realms/helix/protocol/openid-connect/userinfo",
        "RedirectURI": "https://portainer.helix",
        "UserIdentifier": "sub",
        "Scopes": "openid profile email groups",
        "OAuthAutoCreateUsers": true,
        "DefaultTeamID": 1
      }
    }
  post-deployment-notes.txt: |
    Portainer OIDC Configuration:
    
    1. Access Portainer at: https://portainer.helix
    2. On first login, configure OAuth in Portainer settings:
       - Client ID: portainer-oidc
       - Authorization URL: https://keycloak.helix/realms/helix/protocol/openid-connect/auth
       - Access Token URL: https://keycloak.helix/realms/helix/protocol/openid-connect/token
       - Resource URL: https://keycloak.helix/realms/helix/protocol/openid-connect/userinfo
       - Redirect URL: https://portainer.helix
       - User Identifier: sub
       - Scopes: openid profile email groups
    
    3. Client Secret can be retrieved from Keycloak admin console:
       https://keycloak.helix/admin/realms/helix/clients
    
    4. Admin credentials (if needed) are stored in Vault:
       vault kv get secret/keycloak/admin
EOF
)
    
    echo "$oidc_config" | kubectl apply -f - || {
        print_info "⚠️ ConfigMap creation failed, but this is not critical for basic functionality"
    }
    
    print_info "📋 OIDC configuration guide created in ConfigMap: portainer-oidc-config"
    print_info "💡 View with: kubectl get configmap portainer-oidc-config -n $NAMESPACE -o yaml"
}

# --- Keycloak Integration ---
# register_oidc_client: Registers an OIDC client in Keycloak
register_oidc_client() {
    local client_id="$1"
    local redirect_urls="$2"
    local client_description="${3:-Auto-registered client for $NAME}"
    
    [[ -z "$client_id" || -z "$redirect_urls" ]] && {
        print_error "register_oidc_client requires: client_id, redirect_urls" "" 1
    }
    
    print_info "🔐 Registering OIDC client '$client_id' in Keycloak..."
    
    # Get Keycloak admin credentials from environment or Vault
    local keycloak_host="https://keycloak.helix"
    local realm="helix"
    local admin_user="${KEYCLOAK_ADMIN_USER:-admin}"
    local admin_pass="${KEYCLOAK_ADMIN_PASSWORD:-admin}"
    
    # Try to get admin password from Vault if not in environment
    if [[ -z "$admin_pass" ]]; then
        print_info "📦 Attempting to retrieve Keycloak admin password from Vault..."
        if command -v vault >/dev/null 2>&1; then
            admin_pass=$(vault kv get -field=password secret/keycloak/admin 2>/dev/null || echo "")
        fi
        
        if [[ -z "$admin_pass" ]]; then
            print_error "Keycloak admin password not found in environment or Vault" \
                      "Set KEYCLOAK_ADMIN_PASSWORD or store in Vault at secret/keycloak/admin" 1
        fi
    fi
    
    # Get access token from Keycloak
    print_info "🎫 Authenticating with Keycloak admin API..."
    local token
    token=$(curl -s -X POST "$keycloak_host/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=$admin_user" \
        -d "password=$admin_pass" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" | jq -r '.access_token // empty' 2>/dev/null)
    
    if [[ -z "$token" || "$token" == "null" ]]; then
        print_error "Failed to authenticate with Keycloak admin API" \
                  "Check Keycloak availability and admin credentials" 1
    fi
    
    print_success "✅ Successfully authenticated with Keycloak"
    
    # Check if client already exists
    local existing_client
    existing_client=$(curl -s -X GET "$keycloak_host/admin/realms/$realm/clients?clientId=$client_id" \
        -H "Authorization: Bearer $token" | jq -r '.[0].id // empty' 2>/dev/null)
    
    if [[ -n "$existing_client" && "$existing_client" != "null" ]]; then
        print_info "⚠️ OIDC client '$client_id' already exists in Keycloak (ID: $existing_client)"
        print_success "✅ OIDC client registration completed (already exists)"
        return 0
    fi
    
    # Create new OIDC client
    print_info "➕ Creating new OIDC client '$client_id'..."
    local client_json=$(cat <<EOF
{
  "clientId": "$client_id",
  "name": "$client_description",
  "description": "Auto-registered OIDC client for $NAME service",
  "enabled": true,
  "clientAuthenticatorType": "client-secret",
  "redirectUris": ["$redirect_urls"],
  "webOrigins": ["https://*.helix"],
  "protocol": "openid-connect",
  "publicClient": false,
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": true,
  "serviceAccountsEnabled": false,
  "authorizationServicesEnabled": false,
  "fullScopeAllowed": true,
  "nodeReRegistrationTimeout": -1,
  "defaultClientScopes": ["web-origins", "role_list", "profile", "roles", "email"],
  "optionalClientScopes": ["address", "phone", "offline_access", "microprofile-jwt"]
}
EOF
)
    
    local create_response
    create_response=$(curl -s -w "%{http_code}" -X POST "$keycloak_host/admin/realms/$realm/clients" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$client_json")
    
    local http_code="${create_response: -3}"
    if [[ "$http_code" == "201" ]]; then
        print_success "✅ OIDC client '$client_id' created successfully in Keycloak"
        print_info "🔗 Client configured for: $redirect_urls"
        print_info "🌐 Realm: $realm"
        print_info "🎯 Available at: $keycloak_host/admin/realms/$realm/clients"
    else
        print_error "Failed to create OIDC client '$client_id'" \
                  "HTTP code: $http_code. Check Keycloak logs and admin permissions" 1
    fi
}
