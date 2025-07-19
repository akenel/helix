#!/bin/bash
# 🧠 Helix Environment Loader — Robust Bootstrap for Paths, Env, Info
# helix_v3\bootstrap\utils\bootstrap_env_loader.sh
# Ensure this script can be sourced from anywhere
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
# Assume root is one level up from utils (bootstrap/)
HELIX_ROOT_DIR="$(dirname "${SCRIPT_DIR}")"

export HELIX_ROOT_DIR

# You can then reference things like:
# "${HELIX_ROOT_DIR}/utils/some_script.sh"

# ─────── Runtime Detection (Safe Defaults + API) ──────────────
HOST_IP=$(curl -s ifconfig.me || echo "Unknown")
LINUX_INFO=$(uname -srvmo)
DOCKER_VER=$(docker --version 2>/dev/null || echo "Docker not installed")

# Geo from ipinfo
GEO_JSON=$(curl -s https://ipinfo.io 2>/dev/null || echo "{}")
CITY=$(echo "$GEO_JSON" | jq -r '.city // "Unknown"')
REGION=$(echo "$GEO_JSON" | jq -r '.region // "Unknown"')
COUNTRY=$(echo "$GEO_JSON" | jq -r '.country // "Unknown"')

# Weather from wttr.in
WEATHER=$(curl -s "https://wttr.in/?format=j1" 2>/dev/null || echo "{}")
TEMP=$(echo "$WEATHER" | jq -r '.current_condition[0].temp_C // "N/A"')
WIND=$(echo "$WEATHER" | jq -r '.current_condition[0].windspeedKmph // "N/A"')

# Export for downstream use
export HOST_IP LINUX_INFO DOCKER_VER CITY REGION COUNTRY TEMP WIND

# ─────── Friendly System Summary ──────────────
echo ""
echo "📡 System Snapshot Loaded:"
echo "🔹 IP Address     : $HOST_IP"
echo "🔹 Location       : $CITY, $REGION, $COUNTRY"
echo "🔹 Temperature    : $TEMP°C"
echo "🔹 Wind Speed     : $WIND km/h"
echo "🔹 Docker Version : $DOCKER_VER"
echo "📦 Root Directory : $HELIX_ROOT_DIR"
echo "🐧 Linux Active Release 📡 latest updated current distro information :
🐧 $LINUX_INFO"

echo ""
sleep 5