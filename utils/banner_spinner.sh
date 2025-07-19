#!/bin/bash
banner_spinner() {
    local message="$1"
    local command="$2"
    local spinner=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local delay=0.1
    local pid spin_index=0

    # Start command in background
    eval "$command" &
    pid=$!

    # Trap cleanup
    trap "kill $pid 2>/dev/null" EXIT

    # Display spinner while command runs
    tput civis  # Hide cursor
    echo -ne " $message "
    while kill -0 $pid 2>/dev/null; do
        printf "\r %s %s" "${spinner[spin_index]}" "$message"
        spin_index=$(( (spin_index + 1) % ${#spinner[@]} ))
        sleep "$delay"
    done
    wait $pid
    exit_code=$?
    tput cnorm  # Restore cursor
    trap - EXIT

    if [[ $exit_code -eq 0 ]]; then
        printf "\r✅ %s\n" "$message"
    else
        printf "\r❌ %s\n" "$message"
        return $exit_code
    fi
}
