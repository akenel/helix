# ~/helix_v3/utils/bootstrap/spinner_utils.sh

# Global variable to control debug logging
# This should be set by the main script (e.g., 00_run_all_steps.sh)
# before sourcing this file. Default to false if not set.
HELIX_DEBUG="${HELIX_DEBUG:-false}"
# echo "Spinner /\(.\)/"
# Spinner variables
_spinner_pid=""
_spinner_delay="0.2"
_spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

# Start a background spinner
start_spinner() {
  local message="$1"
  echo -n "$message "
  (
    while true; do
      for char in $(echo "$_spinner_chars" | sed -e 's/\(.\)/\1 /g'); do
        echo -en "\b$char"
        sleep "$_spinner_delay"
      done
    done
  ) &
  _spinner_pid=$!
}

# Stop the spinner and print status
stop_spinner() {
  # Correct way to declare local variable with a default value for $1
  local exit_code="${1:-1}" # Default to 1 (failure) if no exit code is provided
  local operation_message="${2:-Service Operation}" # Optional: if you want a message for the spinner stop

  if [[ -n "$_spinner_pid" ]]; then
    kill "$_spinner_pid" > /dev/null 2>&1
    wait "$_spinner_pid" 2>/dev/null
    echo -en "\b" # Erase the last spinner char
  fi
  if [[ "$exit_code" -eq 0 ]]; then
    echo -e "✅" # Success checkmark
  else
    echo -e "❌" # Failure cross
  fi
}

# Logging functions
log_info() {
  if [[ "$HELIX_DEBUG" = "true" ]]; then
    echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S %Z') $1"
  fi
}

log_success() {
  echo "[SUCCESS] $(date +'%Y-%m-%d %H:%M:%S %Z') $1"
}

log_warn() {
  echo "[WARN] $(date +'%Y-%m-%d %H:%M:%S %Z') $1" >&2
}

log_error() {
  echo "[ERROR] $(date +'%Y-%m-%d %H:%M:%S %Z') $1" >&2
}