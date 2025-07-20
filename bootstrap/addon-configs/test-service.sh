#!/usr/bin/env bash
# Sherlock Helix Plugin Tester

set -euo pipefail
IFS=$'\n\t'

# --- Globals for test-service.sh itself ---
TEST_SCRIPT_PATH="${BASH_SOURCE[0]}"
TEST_SCRIPT_DIR="$(cd "$(dirname "$TEST_SCRIPT_PATH")" && pwd)"

# Define the path to install-service.sh relative to this test script's directory
INSTALL_SERVICE_SCRIPT="$TEST_SCRIPT_DIR/install-service.sh"

PLUGIN="$1"
shift || true

SILENT=false
DEBUG=false
HELP=false
# --- Parse CLI Flags ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --silent) SILENT=true; shift ;;
        --debug)  DEBUG=true; shift ;;
        --help)   HELP=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Help Output ---
if [[ "$HELP" == true ]]; then
    cat <<EOF
Usage: ./test-service.sh <plugin> [--silent] [--debug] [--help]

Runs a full test sequence for a Helix plugin:
  - Validates Helm dry-run
  - Installs plugin
  - Upgrades plugin
  - Uninstalls plugin
  - Edits plugin config
  - Lists plugins

Flags:
  --silent   Suppress spinner output and jokes
  --debug    Enable detailed Helm logs
  --help     Show this help message
EOF
    exit 0
fi

# --- Spinner Mock (if SILENT) ---
if [[ "$SILENT" == true ]]; then
    spin() { wait "$1"; }
fi

# --- Output Helpers ---
print_title()   { echo -e "\n🧪 $1"; }
print_pass()    { echo -e "✅ $1"; }
print_fail()    { echo -e "❌ $1"; return 1; }
print_info()    { echo -e "ℹ️  $1"; }

# --- Run Step ---
# --- Run Step ---
run_step() {
    local title="$1"
    local command="$2"

    print_title "$title"
    # Ensure command uses the defined INSTALL_SERVICE_SCRIPT variable
    # We replace the placeholder "./install-service.sh" with "$INSTALL_SERVICE_SCRIPT"
    local full_command
    full_command=$(echo "$command" | sed "s#\./install-service.sh#$INSTALL_SERVICE_SCRIPT#g")

    if eval "$full_command"; then # Use the modified command
        print_pass "$title"
    else
        print_fail "Failed: $title"
        return 1
    fi
}


# --- Begin Testing ---
print_info "🧪 Starting full test suite for plugin: '$PLUGIN'"
[[ "$DEBUG" == true ]] && print_info "🔍 Debug mode enabled"

# Run each major action
# Run each major action
FAILED=false

# Update these calls to *not* use "./install-service.sh" directly
# Instead, we just pass the arguments and let `run_step` handle the script path.
# OR, make run_step directly construct the command with INSTALL_SERVICE_SCRIPT.
# Let's simplify run_step.

# REVISED run_step logic to build the command explicitly:
run_step() {
    local title="$1"
    local script_args="$2" # Now expects only the arguments to install-service.sh

    print_title "$title"
    local command_to_execute="$INSTALL_SERVICE_SCRIPT $script_args"

    if eval "$command_to_execute"; then
        print_pass "$title"
    else
        print_fail "Failed: $title"
        return 1
    fi
}

# And then, the calls in the main body become:
run_step "Validating Helm dry-run..." "--plug $PLUGIN --validate-only $([[ $DEBUG == true ]] && echo --debug)" || FAILED=true
run_step "Installing plugin..."    "--plug $PLUGIN $([[ $DEBUG == true ]] && echo --debug)" || FAILED=true
run_step "Upgrading plugin..."       "--plug $PLUGIN --upgrade $([[ $DEBUG == true ]] && echo --debug)" || FAILED=true
run_step "Uninstalling plugin..."    "--plug $PLUGIN --uninstall $([[ $DEBUG == true ]] && echo --debug)" || FAILED=true
run_step "Editing plugin config..."  "--plug $PLUGIN --edit" || FAILED=true
run_step "Listing plugins..."        "--list" || FAILED=true # --list does not need --plug

# --- Farewell ---
if [[ "$FAILED" == true ]]; then
    echo -e "\n💣 Some steps failed for plugin '$PLUGIN'. Use --debug to troubleshoot."
    [[ "$SILENT" != true ]] && echo -e "🕵️‍♂️ \"Eliminate all other factors, and the one which remains must be the truth.\" – Sherlock Holmes"
    exit 1
else
    [[ "$SILENT" != true ]] && echo -e "\n🎉 All tests passed for plugin '$PLUGIN'! You're an automation detective, my dear Watson."
    [[ "$SILENT" != true ]] && curl -s https://api.chucknorris.io/jokes/random | jq -r '.value' | sed 's/^/🤣 Chuck Norris: /'
    exit 0
fi
