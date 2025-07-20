#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Starting test plugin lifecycle..."
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/bootstrap/addon-configs/install-service.sh"

PLUGIN_NAME="portainer"

echo "📦 TEST 1: List plugins (from root)"
"$INSTALLER" --list

echo "🧪 TEST 2: Validate plugin (from root)"
"$INSTALLER" --plug "$PLUGIN_NAME" --validate-only --debug

echo "🚀 TEST 3: Install plugin (from root)"
"$INSTALLER" --plug "$PLUGIN_NAME" --install --debug

echo "🔁 TEST 4: Upgrade dry-run (from nested dir)"
cd "$ROOT/bootstrap/addon-configs"
"$INSTALLER" --plug "$PLUGIN_NAME" --upgrade --validate-only --debug

echo "🗑️ TEST 5: Uninstall plugin (from root)"
cd "$ROOT"
"$INSTALLER" --plug "$PLUGIN_NAME" --uninstall --debug

echo "❌ TEST 6: Handle unknown plugin (error expected)"
set +e
"$INSTALLER" --plug not-a-real-plugin --validate-only
set -e

echo "✅ All tests executed."
