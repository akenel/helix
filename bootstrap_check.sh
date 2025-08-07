#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# 📦 Helix Preflight Bootstrap System Check
set -euo pipefail
IFS=$'\n\t'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_ok()    { echo -e "${GREEN}✅ $1${NC}"; }
print_warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

echo -e "\n🔍 ${YELLOW}Helix System Preflight Check${NC}\n"

# 1. Docker check
if ! command -v docker >/dev/null; then
  print_error "Docker is not installed or not in PATH."
else
  if ! docker info >/dev/null 2>&1; then
    print_error "Docker is installed but not running. Please start Docker Desktop and ensure WSL2 integration is enabled."
  else
    print_ok "Docker is installed and running."
  fi
fi

# 2. WSL Integration check (for Windows users)
if grep -qEi "(Microsoft|WSL)" /proc/version &>/dev/null; then
  if ! docker info >/dev/null 2>&1; then
    print_warn "You're running inside WSL, but Docker cannot connect. Check Docker Desktop → Settings → Resources → WSL Integration."
  fi
  print_ok "WSL environment detected."
fi

# 3. Tooling checks
for tool in mkcert helm jq yq k3d; do
  if ! command -v "$tool" >/dev/null; then
    print_error "$tool is not installed."
  else
    print_ok "$tool is installed."
  fi
done

# 4. mkcert CA check
if command -v mkcert >/dev/null; then
  CAROOT=$(mkcert -CAROOT)
  if [[ -f "$CAROOT/rootCA.pem" ]]; then
    print_ok "mkcert root CA found at $CAROOT"
  else
    print_warn "mkcert installed, but root CA not found. Try running: mkcert -install"
  fi
fi

# 5. Check executable flags on .sh scripts
SCRIPT_COUNT=$(find . -name "*.sh" | wc -l)
EXECUTABLE_COUNT=$(find . -name "*.sh" -executable | wc -l)

if [[ "$SCRIPT_COUNT" -ne "$EXECUTABLE_COUNT" ]]; then
  print_warn "Some .sh scripts are missing +x permission. Run: chmod +x \$(find . -name '*.sh')"
else
  print_ok "All .sh scripts have executable permission."
fi

# 6. Optional: Check if ./run.sh exists
if [[ -f "./run.sh" ]]; then
  if [[ -x "./run.sh" ]]; then
    print_ok "./run.sh is present and executable."
  else
    print_warn "./run.sh exists but is not executable. Run: chmod +x ./run.sh"
  fi
else
  print_warn "No ./run.sh found — this may not be the root Helix directory."
fi

echo -e "\n🧠 ${GREEN}Helix preflight check complete.${NC}"
echo -e "🐳 ${GREEN}Ready to bootstrap your Helix environment!${NC}\n"
# ─────── Bootstrap Environment Loader ──────────────
# This script loads the Helix environment and gathers system info.
# It should be sourced from anywhere in the Helix project.
# Ensure this script is sourced, not executed directly.