#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# 🌀 Spinner + Logging Utility (Sherlock TLC Edition) — Revised for Resilience
# ------------------------------------------------------------------------------

# 🕰 Timestamp helper
timestamp() {
  date +"%Y-%m-%d %H:%M:%S %Z"
}

# 📢 Log Levels
log_info()    { echo -e "[INFO]    $(timestamp) $*"; }
log_warn()    { echo -e "\033[1;33m[WARN]    $(timestamp) $*\033[0m"; }
log_error()   { echo -e "\033[1;31m[ERROR]   $(timestamp) $*\033[0m" >&2; }
log_success() { echo -e "\033[1;32m[SUCCESS] $(timestamp) $*\033[0m"; }

# 🌀 Spinner globals
SPINNER_PID=""
SPINNER_CHARS=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
SPINNER_DELAY=0.1

# 🌀 Start spinner with a message
start_spinner() {
  local msg="${*:-}"
  local i=0

  if [[ -z "$msg" ]]; then
    log_warn "start_spinner called without a message. Spinner will still run."
    msg="Working..."
  fi

  printf "\r⏳ %s" "$msg"
  (
    while true; do
      printf "\r%s %s" "${SPINNER_CHARS[i]}" "$msg"
      i=$(( (i + 1) % ${#SPINNER_CHARS[@]} ))
      sleep "$SPINNER_DELAY"
    done
  ) &
  SPINNER_PID=$!
  disown "$SPINNER_PID"
}

# ✅ Stop spinner and print status
stop_spinner() {
  local status="${1:-1}"  # Default to failure if unset

  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" >/dev/null 2>&1 || true
    wait "$SPINNER_PID" 2>/dev/null || true
    unset SPINNER_PID
  fi

  if [[ "$status" == "0" ]]; then
    printf "\r\033[1;32m✅ Done!\033[0m\n"
  else
    printf "\r\033[1;31m❌ Failed.\033[0m\n"
  fi
}

# 🧹 Clean spinner without printing success/fail
stop_spinner_quietly() {
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" >/dev/null 2>&1 || true
    wait "$SPINNER_PID" 2>/dev/null || true
    unset SPINNER_PID
    printf "\r"
  fi
}
