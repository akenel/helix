#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

# 🔧 Helix Plugin Installer – Sherlock Edition
set -euo pipefail
IFS=$'\n\t'

# --- Output Functions ---
# print_info: Prints informational messages.
# Arguments:
#   $1 - The message string.
print_info()     { echo -e "ℹ️  $1"; }

# print_success: Prints success messages.
# Arguments:
#   $1 - The message string.
print_success()  { echo -e "✅ $1"; }

# print_error: Prints error messages, optionally includes a debug tip and exits.
# Arguments:
#   $1 - The primary error message.
#   $2 - (Optional) A detailed debug tip or suggestion.
#   $3 - (Optional) The exit code (defaults to 1).
print_error() {
    local message="$1"
    local debug_tip="$2" # This is the second argument
    local exit_code="${3:-1}" # This is the third argument, defaulting to 1

    echo -e "❌ ERROR: $message" >&2 # Print error message to stderr

    # If a full log file path is available and the file exists, display its tail.
    if [[ -n "$FULL_LOG_FILE" && -f "$FULL_LOG_FILE" ]]; then
        echo -e "\n--- BEGIN Operation Log ($FULL_LOG_FILE) ---" >&2
        tail -n 50 "$FULL_LOG_FILE" >&2 # Show the last 50 lines from the log
        echo -e "--- END Operation Log ---" >&2
    fi

    # If a debug tip is provided, print it.
    if [[ -n "$debug_tip" ]]; then
        echo -e "\n💡 TIP: $debug_tip" >&2
    fi
    echo -e "\nFor more detailed debugging, run this script with the --debug flag." >&2

    # Ensure exit_code is truly numeric before exiting.
    # This prevents "numeric argument required" errors if an invalid exit_code is passed.
    if [[ "$exit_code" =~ ^[0-9]+$ ]]; then
        exit "$exit_code"
    else
        echo "Internal error: Non-numeric exit code provided to print_error. Exiting with 1." >&2
        exit 1
    fi
}

# print_usage: Displays the script's usage instructions and exits.
print_usage() {
    cat <<EOF
Usage: $0 --plug <name> [--debug] [--list] [--uninstall] [--upgrade] [--edit] [--create] [--validate-only] [--help]
Options:
  --plug <name>          Specify plugin name (required unless --list, --create)
  --debug                Enable verbose Helm output and atomic install/upgrade
  --list                 List all enabled plugins
  --edit                 Edit the plugin's values.yaml (requires --plug)
  --create               Wizard to create a new plugin entry
  --validate-only        Dry-run validate Helm command only (no install)
  --upgrade              Upgrade plugin (requires --plug)
  --uninstall            Uninstall plugin (requires --plug)
  --help                 Show help
EOF
    exit 1
}

# print_summary: Displays a summary of the completed plugin operation.
# Relies on global variables populated by other functions (NAME, NAMESPACE, etc.).
print_summary() {
    echo -e "\n🎉 Plugin '$NAME' operation completed successfully!"
    echo "📜 Plugin Name: $NAME"
    echo "🗂 Namespace: $NAMESPACE"
    echo "📄 Values file: $VALUES_PATH"
    echo "📂 Logs: $FULL_LOG_FILE"
    [[ -n "$NOTES" && "$NOTES" != "null" ]] && echo -e "📘 Notes:\n$NOTES"
    echo ""
    echo "🔗 URL: https://$NAME.helix" # Assuming this general pattern
    echo "📖 Docs: https://github.com/akenel/helix/tree/main/docs"
    echo "🧼 Uninstall: $0 --uninstall $NAME"
    echo "🔄 Upgrade: $0 --upgrade $NAME"
    echo "🔍 Debug: $0 --plug $NAME --debug"
    echo "📦 All plugins: $0 --list"
    echo "💬 Community: https://github.com/akenel/helix"

    # --- NEW: Include Kubernetes Client/Server Version Skew Info ---
    local client_version=$(kubectl version --client -o json | yq -r '.clientVersion.gitVersion // "N/A"')
    local server_version=$(kubectl version --short -o json | yq -r '.serverVersion.gitVersion // "N/A"')
    
    echo -e "\n--- Environment Health Check ---"
    echo "Kubectl Client Version: $client_version"
    echo "Kubectl Server Version: $server_version"
    if [[ "$client_version" != "N/A" && "$server_version" != "N/A" ]]; then
        local client_minor=$(echo "$client_version" | sed -E 's/v[0-9]+\.([0-9]+)\..*/\1/')
        local server_minor=$(echo "$server_version" | sed -E 's/v[0-9]+\.([0-9]+)\..*/\1/')
        if (( client_minor > server_minor + 1 || client_minor < server_minor - 1 )); then
            echo "⚠️  WARNING: Kubectl client/server version skew exceeds recommended +/-1 minor version."
            echo "   This might lead to unexpected behavior or compatibility issues."
            echo "   Consider upgrading/downgrading your kubectl client to match the server version more closely."
        else
            echo "✅ Kubectl client/server version skew is within recommended limits."
        fi
    else
        echo "ℹ️  Could not determine kubectl client/server versions for skew check."
    fi

    local helm_version=$(helm version --template '{{.Version}}' // "N/A")
    echo "Helm Version: $helm_version"
    # Add more checks here as needed, e.g., yq version, docker version
    echo "YQ Version: $(yq --version | head -n 1)"
    echo "Docker Version: $(docker --version | head -n 1)"
    echo "--- End Environment Health Check ---"
}
