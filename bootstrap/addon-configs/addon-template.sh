#!/bin/bash
# 🧩 Helix Add-on Installer Template
# 📜 Usage: ./addon-template.sh [--dry-run] [--debug] [--status]
# 📦 Scaffold for modular Helm/Kustomize/Kubectl add-ons
set -euo pipefail

# ─── 🧠 Configurable Variables ─────────────────────────────
ADDON_NAME="example-service"
NAMESPACE="addons"
CHART_REPO="bitnami/example"
RELEASE_NAME="${ADDON_NAME}"
VALUES_FILE="./addons/configs/${ADDON_NAME}-values.yaml"
DRYRUN=false
DEBUG=false
STATUS=false

# ─── 🧪 Parse CLI Arguments ────────────────────────────────
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run) DRYRUN=true ;;
    --debug)   DEBUG=true ;;
    --status)  STATUS=true ;;
    --help|-h)
      echo "🔧 Usage: $0 [--dry-run] [--debug] [--status]"
      exit 0
      ;;
    *) echo "❌ Unknown argument: $1" && exit 1 ;;
  esac
  shift
done

# ─── 📢 Logging Helpers ─────────────────────────────────────
log()    { echo "[🕵️‍♂️ $(date +%H:%M:%S)] $*"; }
debug()  { $DEBUG && echo "[🐛 DEBUG] $*"; }
announce() { echo -e "\n🔹 $1\n"; }

# ─── 📊 Status Mode ─────────────────────────────────────────
if $STATUS; then
  announce "🔍 Helm status for $RELEASE_NAME"
  helm status "$RELEASE_NAME" -n "$NAMESPACE" || echo "ℹ️ Not installed"
  echo ""
  kubectl get pods -n "$NAMESPACE" || true
  exit 0
fi

# ─── 🧪 Dry Run Mode ────────────────────────────────────────
if $DRYRUN; then
  announce "🧪 Simulating Helm install (dry-run)"
  helm upgrade --install "$RELEASE_NAME" "$CHART_REPO" \
    -n "$NAMESPACE" --create-namespace \
    -f "$VALUES_FILE" --dry-run --debug
  exit 0
fi

# ─── 🚀 Install Add-On ─────────────────────────────────────
announce "📦 Installing Add-On: $ADDON_NAME"

debug "Using chart: $CHART_REPO"
debug "Namespace: $NAMESPACE"
debug "Values file: $VALUES_FILE"

helm upgrade --install "$RELEASE_NAME" "$CHART_REPO" \
  -n "$NAMESPACE" --create-namespace \
  -f "$VALUES_FILE" --wait --timeout=300s

announce "✅ $ADDON_NAME installed successfully"
kubectl get svc,pods -n "$NAMESPACE"
