#!/usr/bin/env bash
# 🧭 set-kubeconfig.sh — Central kubeconfig handler for HELIX
# This script defines a function to set KUBECONFIG, intended to be sourced.

# No global echo statements here. All output should come from within functions
# or be handled by the calling script.

# Define the function to set kubeconfig environment variables
_set_kubeconfig_env() {
  # No echo for "Inside Sub/MAIN" here. This function should focus on setting the env.
  local CLUSTER="${1:-helix}"
  local CONFIG_DIR="$HOME/.kube/configs"
  local DEFAULT_PATH="$HOME/.helix/kubeconfig.yaml"
  local ALT_PATH="$CONFIG_DIR/k3d-${CLUSTER}.yaml"
  local KUBECONFIG_PATH=""

  # Decide path priority
  if [[ -f "$ALT_PATH" ]]; then
    KUBECONFIG_PATH="$ALT_PATH"
  elif [[ -f "$DEFAULT_PATH" ]]; then
    KUBECONFIG_PATH="$DEFAULT_PATH"
  else
    # Use log_error from spinner_utils.sh if sourced before this script
    # Otherwise, fall back to simple echo
    if command -v log_error >/dev/null 2>&1; then
      log_error "Kubeconfig not found for cluster '$CLUSTER'."
      log_error "Looked in: $ALT_PATH and $DEFAULT_PATH"
      log_error "Hint: Try running: ./bootstrap/01_create-cluster.sh"
    else
      echo "❌ Kubeconfig not found for cluster '$CLUSTER'." >&2
      echo "🔍 Looked in: $ALT_PATH and $DEFAULT_PATH" >&2
      echo "💡 Try running: ./bootstrap/01_create-cluster.sh" >&2
    fi
    return 1 # Indicate failure
  fi

  # Set the environment variables globally for the current shell
  export HELIX_KUBECONFIG_PATH="$KUBECONFIG_PATH"
  export KUBECONFIG="$KUBECONFIG_PATH"
echo "Completed \helix\bootstrap\utils\set-kubeconfig.sh" 
  # No direct echo for "🔍 Look KUBECONFIG" here. Let the calling script handle feedback.
  return 0 # Indicate success
}
