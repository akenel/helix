#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="bootstrap/addon-configs/services.yaml"
SPINNER_SCRIPT="utils/core/spinner.sh"
SERVICE=""
DEBUG=false

# Parse Flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plug) SERVICE="$2"; shift 2 ;;
    --debug) DEBUG=true; shift ;;
    --list)
      echo "📦 Available plugins:"
      yq '.plugins[] | "\(.name): \(.description)"' "$CONFIG_FILE"
      exit 0
      ;;
    *) echo "❌ Unknown option: $1"; exit 1 ;;
  esac
done

# Validate
if [[ -z "$SERVICE" ]]; then echo "❌ No plugin specified. Use: --plug <name>"; exit 1; fi
if ! yq ".plugins[] | select(.name==\"$SERVICE\")" "$CONFIG_FILE" >/dev/null; then
  echo "❌ Plugin '$SERVICE' not found in $CONFIG_FILE"; exit 1
fi

# Extract
PLUGIN_NAME=$(yq -r ".plugins[] | select(.name==\"$SERVICE\") | .name" "$CONFIG_FILE")
PLUGIN_DESC=$(yq -r ".plugins[] | select(.name==\"$SERVICE\") | .description" "$CONFIG_FILE")
PLUGIN_CHART=$(yq -r ".plugins[] | select(.name==\"$SERVICE\") | .chart" "$CONFIG_FILE")
PLUGIN_VERSION=$(yq -r ".plugins[] | select(.name==\"$SERVICE\") | .version" "$CONFIG_FILE")
PLUGIN_NAMESPACE=$(yq -r ".plugins[] | select(.name==\"$SERVICE\") | .namespace" "$CONFIG_FILE")
VALUES_FILE=$(yq -r ".plugins[] | select(.name==\"$SERVICE\") | .values_file" "$CONFIG_FILE")

# Show Info
echo "☕ Installing plugin 🥐 $PLUGIN_NAME — $PLUGIN_DESC"
echo "📦 Chart     : $PLUGIN_CHART"
echo "📦 Version   : $PLUGIN_VERSION"
echo "📦 Namespace : $PLUGIN_NAMESPACE"
echo "📄 Values    : $VALUES_FILE"
echo ""

[[ -f "$VALUES_FILE" ]] || { echo "❌ Values file not found: $VALUES_FILE"; exit 1; }

# Build Helm Command
HELM_CMD="helm upgrade --install \"$PLUGIN_NAME\" \"$PLUGIN_CHART\" \
  --version \"$PLUGIN_VERSION\" \
  --namespace \"$PLUGIN_NAMESPACE\" --create-namespace \
  -f \"$VALUES_FILE\""

[[ "$DEBUG" == "true" ]] && HELM_CMD="$HELM_CMD --debug --atomic"

# Run with Spinner
LOG_FILE="/tmp/helm-$PLUGIN_NAME-$(date +%s).log"
echo "🔧 Running: $HELM_CMD"
bash -c "$HELM_CMD" &> "$LOG_FILE" &
PID=$!

# Run spinner while Helm runs
source "$SPINNER_SCRIPT"
spin "$PID"

# Result Check
wait $PID || {
  echo "❌ Deployment failed for $PLUGIN_NAME"
  echo "📜 Last 20 lines of Helm output:"
  tail -n 20 "$LOG_FILE"
  exit 1
}

echo "✅ $PLUGIN_NAME installed! 🌐 Access: https://$PLUGIN_NAME.helix"
