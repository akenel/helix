#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR
PLUGIN_NAME="chuck"
PLUGIN_DESC="Displays a Chuck Norris joke"

run_plugin() {
  echo "🥋 Chuck Norris mode activated..."
  JOKE=$(curl -s https://api.chucknorris.io/jokes/random | jq -r '.value')
  echo "💬 Chuck says: $JOKE"
}
