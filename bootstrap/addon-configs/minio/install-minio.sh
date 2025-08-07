#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR
PLUGIN_NAME="minio"
PLUGIN_DESC="MinIO: High-performance S3-compatible object store"
  echo "📦 Installing $PLUGIN_DESC..."

run_plugin() {
  echo "📦 Installing $PLUGIN_NAME..."

  # Get path to this plugin script (portable)
  PLUGIN_PATH="$(realpath "${BASH_SOURCE[0]}")"
  PLUGIN_DIR="$(dirname "${PLUGIN_PATH}")"
  HELIX_ROOT="$(realpath "${PLUGIN_DIR}/../..")"

  helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
  helm repo update

  helm upgrade --install minio bitnami/minio \
    --namespace minio --create-namespace \
    -f "${HELIX_ROOT}/addon-configs/minio/minio-values.yaml" || {
      echo "❌ Failed to deploy MinIO"
      return 1
    }

  echo "✅ MinIO installed at https://minio.helix"
}
echo "📦 Now run deployment for $PLUGIN_DESC\n | PLUGIN_PATH: $PLUGIN_PATH \n  | PLUGIN_DIR: $PLUGIN_DIR \n | HELIX_ROOT: $HELIX_ROOT \n "
 run_plugin 