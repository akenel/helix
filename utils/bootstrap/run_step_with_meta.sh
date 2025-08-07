#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR
# 📜 /home/angel/helix/utils/bootstrap/run_step_with_meta.sh
# Sherlock-enhanced for bulletproof execution

echo "Inside $HOME/helix/utils/bootstrap/run_step_with_meta.sh with arguments: $@"

# ─── 🧠 Helper Functions ─────────────────────────

# Deduplicates paths like /a/b/b/c → /a/b/c
deduplicate_path() {
    local input="$1"
    echo "$input" | sed -E 's|(\/[^/]+)(/\1)+|\1|g'
}

# Search fallback dirs for the given script name
find_script_by_name() {
    local name="$1"
    for dir in "${SEARCH_DIRS[@]}"; do
        found=$(find "$dir" -type f -name "$name" 2>/dev/null | head -n 1)
        if [[ -n "$found" ]]; then
            echo "$found"
            return 0
        fi
    done
    return 1
}

# ─── 🛡️ Input Validation ─────────────────────────

if [[ -z "$1" ]]; then
    echo "❌ ERROR: No script path was provided to run_step_with_meta.sh"
    exit 1
fi

SCRIPT_PATH="$1"
SCRIPT_NAME="${SCRIPT_PATH##*/}"
SCRIPT_PATH=$(deduplicate_path "$SCRIPT_PATH")

if [[ ! "$SCRIPT_NAME" =~ \.sh$ ]]; then
    echo "❌ ERROR: Expected a .sh script, got: '$SCRIPT_NAME'"
    exit 1
fi

if [[ "$SCRIPT_PATH" =~ \.sh/ ]]; then
    echo "❌ ERROR: Path looks malformed (double-joined?): '$SCRIPT_PATH'"
    exit 1
fi

# ─── 🔍 Resolve the Correct Script ───────────────

SEARCH_DIRS=(
    "$HOME/helix/bootstrap/utils"
    "$HOME/helix/bootstrap/tests"
    "$HOME/helix/bootstrap/deployment-phases"
    "$HOME/helix/bootstrap/deployment-phases/post-scripts"
    "$HOME/helix/bootstrap/support"
)

if [[ ! -x "$SCRIPT_PATH" ]]; then
    echo "⚠️  Script not found or not executable at '$SCRIPT_PATH'. Attempting fallback search..."
    alt_path=$(find_script_by_name "$SCRIPT_NAME")
    if [[ -n "$alt_path" ]]; then
        echo "✅ Script resolved via fallback: $alt_path"
        SCRIPT_PATH="$alt_path"
    else
        echo "❌ ERROR: Could not locate '$SCRIPT_NAME' in known directories."
        exit 1
    fi
else
    echo "✅ Found script at given or cleaned path: $SCRIPT_PATH"
fi

# ─── ⏱️ Execute the Script ───────────────────────

t0=${SECONDS:-0}
shift  # Remove SCRIPT_PATH from the argument list
"$SCRIPT_PATH" "$@" || {
    t=$((SECONDS - t0))
    echo -e "\n❌ $SERVICE_NAME FAILED in ${t}s\n"
    exit 1
}
t=$((SECONDS - t0))
echo "✅ Step #$STEP_NUM — $SERVICE_NAME completed in ${t}s $SERVICE_EMOJI"
