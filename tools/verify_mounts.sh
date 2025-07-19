#!/bin/bash
# 🕵️ Sherlock's verify_mounts.sh v1.1
# ✅ Improved: Checks mounts, handles missing pods, includes banner & debug

set -euo pipefail

# ──────────────── USAGE ────────────────
show_help() {
  cat <<EOF
🔍 verify_mounts.sh — Keycloak Volume Mount Inspector

Usage:
  ./verify_mounts.sh [--debug]

Description:
  Verifies mounted paths inside the Keycloak pod:
    - /opt/keycloak/themes/<cluster>
    - /opt/keycloak/addon-configs/helix-realm.json

Options:
  --help     Show this help message
  --debug    Enable verbose debug output
EOF
  exit 0
}

spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  while ps -p "$pid" &>/dev/null; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

# ──────────────── Config ────────────────
DEBUG=false
CLUSTER="${CLUSTER:-helix}"
NAMESPACE="${NAMESPACE:-identity}"
MOUNT_PATH_THEME="/opt/keycloak/themes/$CLUSTER"
MOUNT_PATH_REALM="/opt/keycloak/addon-configs/helix-realm.json"

[[ "${1:-}" == "--help" ]] && show_help
[[ "${1:-}" == "--debug" ]] && DEBUG=true

# ──────────────── Pod Discovery ────────────────
if ! kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak | grep -q 'keycloak'; then
  echo "❌ No Keycloak pods found in namespace '$NAMESPACE'"
  echo "💡 Try: kubectl get pods -n $NAMESPACE"
  exit 1
fi

KEYCLOAK_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak \
  -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo "")

if [[ -z "$KEYCLOAK_POD" ]]; then
  echo "❌ Could not determine Keycloak pod name (no pods running?)"
  exit 1
fi

$DEBUG && echo "🧠 Pod: $KEYCLOAK_POD"
$DEBUG && echo "🔎 Checking mounts..."

# ──────────────── Check Functions ────────────────
check_mount() {
  local path="$1"
  local desc="$2"
  echo -n "📁 Inspecting $desc..."
  kubectl exec -n "$NAMESPACE" "$KEYCLOAK_POD" -- ls "$path" &>/dev/null &
  spinner $!
  if wait $!; then
    echo " ✅ Found $desc at $path"
  else
    echo " ❌ Missing $desc at $path"
  fi
}

check_file() {
  local file="$1"
  local desc="$2"
  echo -n "📄 Verifying $desc..."
  kubectl exec -n "$NAMESPACE" "$KEYCLOAK_POD" -- test -f "$file" &>/dev/null &
  spinner $!
  if wait $!; then
    echo " ✅ File $desc is mounted correctly"
  else
    echo " ❌ File $desc not found"
  fi
}

# ──────────────── Run Checks ────────────────
check_mount "$MOUNT_PATH_THEME" "Keycloak Theme Directory"
check_file "$MOUNT_PATH_REALM" "Realm JSON Config"

# ──────────────── Victory Ban
