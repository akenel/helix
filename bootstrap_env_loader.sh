#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR
# 🧠 Helix Environment Loader — Robust Bootstrap for Paths, Env, Info
# bootstrap_env_loader.sh
# Ensure this script can be sourced from anywhere
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
# Assume root is one level up from utils (bootstrap/)
HELIX_ROOT_DIR="$(dirname "${SCRIPT_DIR}")"

export HELIX_ROOT_DIR
echo "🔧 Loading Helix Environment from: $ENV_LOADER_PATH"
# You can then reference things like:
# "${HELIX_ROOT_DIR}/utils/some_script.sh"

# ─────── Runtime Detection (Safe Defaults + API) ──────────────

# Get IP (fallback gracefully)
HOST_IP=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
[[ -z "$HOST_IP" || "$HOST_IP" == *html* ]] && HOST_IP="Unknown"

# Basic OS info
LINUX_INFO=$(uname -srvmo)
DOCKER_VER=$(docker --version 2>/dev/null || echo "Docker not installed")

# --- Geo from ipinfo.io ---
GEO_JSON=$(curl -s https://ipinfo.io 2>/dev/null || echo "{}")
if ! echo "$GEO_JSON" | jq empty >/dev/null 2>&1; then
  echo "⚠️  Warning: Invalid JSON received from ipinfo.io"
  CITY="Unknown"; REGION="Unknown"; COUNTRY="Unknown"
else
  CITY=$(echo "$GEO_JSON" | jq -r '.city // "Unknown"')
  REGION=$(echo "$GEO_JSON" | jq -r '.region // "Unknown"')
  COUNTRY=$(echo "$GEO_JSON" | jq -r '.country // "Unknown"')
fi

# --- Weather from wttr.in ---
WEATHER_JSON=$(curl -s "https://wttr.in/?format=j1" 2>/dev/null || echo "{}")
if ! echo "$WEATHER_JSON" | jq empty >/dev/null 2>&1; then
  echo "⚠️  Warning: Invalid JSON from wttr.in"
  TEMP="N/A"; WIND="N/A"
else
  TEMP=$(echo "$WEATHER_JSON" | jq -r '.current_condition[0].temp_C // "N/A"')
  WIND=$(echo "$WEATHER_JSON" | jq -r '.current_condition[0].windspeedKmph // "N/A"')
fi

# Export for downstream use
export HOST_IP LINUX_INFO DOCKER_VER CITY REGION COUNTRY TEMP WIND

# ─────── Friendly System Summary ──────────────
echo ""
echo "📡 System Snapshot Loaded:"
echo "🔹 IP Address     : $HOST_IP"
echo "🔹 Location       : $CITY, $REGION, $COUNTRY"
echo "🔹 Current Date   : $(date)"
echo "🔹 Current Time   : $(date +'%H:%M:%S')"
echo "🔹 Temperature    : $TEMP°C"
echo "🔹 Wind Speed     : $WIND km/h"
echo "🔹 Docker Version : $DOCKER_VER"
echo "📦 Root Directory : $HELIX_ROOT_DIR"
echo "🔹 Linux Info     : 
$LINUX_INFO"
echo "🧠 Completed bootstrap_env_loader.sh"
echo "🐳"
echo "✨ Grand Helix Platform Environment Loaded 🚀"
# ─────── Keycloak Deployment Phase ──────────────
echo ""
echo "🔑 Keycloak Deployment Phase  "

