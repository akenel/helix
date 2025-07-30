#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR
# 📁 tools/safe_path_resolver.sh
# 🛡️ Resolves and validates critical utility paths.

HELIX_ROOT="${HOME}/helix_v3"
UTILS_PATH="${HELIX_ROOT}/utils/bootstrap"

# Validate existence
if [[ ! -d "$UTILS_PATH" ]]; then
  echo "❌ ERROR: Expected utils path not found at $UTILS_PATH"
  exit 1
fi

# Output usable path
echo "$UTILS_PATH"

# ────────────────────────────────────────────────
# ✅ USAGE:
#   source safe_path_resolver.sh
#   resolved=$(resolve_file_path "/bad/path/config.yaml" "config.yaml")
# ────────────────────────────────────────────────

# Known fallback search roots
FALLBACK_DIRS=(
    "$HOME/helix_v3"
    "$HOME/helix_v3/bootstrap"
    "$HOME/helix_v3/bootstrap/utils"
    "$HOME/helix_v3/bootstrap/deployment-phases"
    "$HOME/helix_v3/bootstrap/deployment-phases/post-scripts"
    "$HOME/helix_v3/bootstrap/support"
    "$HOME/helix_v3/bootstrap/addon-configs"
    "$HOME/helix_v3/bootstrap/tests"
)

# ─────── Options ───────
SAFE_PATH_DEBUG=false

# ─────── Help ───────
safe_path_help() {
  cat <<EOF
🧭 safe_path_resolver.sh — Resilient Sherlockian File Finder

Usage:
    source safe_path_resolver.sh
    resolve_file_path <path_or_guess> <filename> [--debug]

Options:
    --help         Show this help message
    --debug        Enable debug output

Example:
    resolve_file_path "./bad/path/script.sh" "script.sh" --debug

Returns:
    The resolved full path to the file if found
    Exits with code 1 if not found

EOF
}

# ─────── Deduplicator ───────
deduplicate_path() {
    local input="$1"
    echo "$input" | sed -E 's|(\/[^/]+)(/\1)+|\1|g'
}

# ─────── Main Resolver ───────
resolve_file_path() {
    local input_path="${1:-}"
    local filename="${2:-$(basename "$input_path")}"
    local flag="${3:-}"

    echo "'$1' <path_or_guess>"
    echo "'$2' <filename>"
    echo "'$3' [--debug]"

    [[ "$input_path" == "--help" || "$filename" == "--help" ]] && safe_path_help && return 0
    [[ "$flag" == "--debug" ]] && SAFE_PATH_DEBUG=true

    if [[ -z "$input_path" || -z "$filename" ]]; then
        echo "❌ ERROR: resolve_file_path requires a path and filename."
        return 1
    fi

    # Step 1: Deduplicate the input path
    local clean_path
    clean_path=$(deduplicate_path "$input_path")

    $SAFE_PATH_DEBUG && echo "🔍 Deduplicated path: $clean_path"

    # Step 2: If it exists as-is
    if [[ -e "$clean_path" ]]; then
        $SAFE_PATH_DEBUG && echo "✅ Path exists: $clean_path"
        echo "$clean_path"
        return 0
    fi

    $SAFE_PATH_DEBUG && echo "⚠️  '$clean_path' not found. Searching known directories for '$filename'..."

    # Step 3: Search known fallback dirs
    for dir in "${FALLBACK_DIRS[@]}"; do
        match=$(find "$dir" -type f -name "$filename" 2>/dev/null | head -n 1)
        if [[ -n "$match" ]]; then
            $SAFE_PATH_DEBUG && echo "✅ Match found: $match"
            echo "$match"
            return 0
        fi
    done

    echo "❌ ERROR: Could not locate file '$filename' anywhere in fallback directories."
    return 1
}
