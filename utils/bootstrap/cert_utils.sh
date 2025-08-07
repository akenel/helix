#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR
# bootstrap\utils\cert_utils.shh
ensure_mkcert_tls_secret() {
  local name="$1"
  local host="$2"
  local ns="$3"
  local dir="$HOME/helix/bootstrap/certs/${name}"
  mkdir -p "$dir"
  [[ ! -f "$dir/${host}.pem" || ! -f "$dir/${host}-key.pem" ]] && (
    echo "🔐 Creating cert for $host..."
    pushd "$dir" >/dev/null
    mkcert "$host"
    popd >/dev/null
  )
  kubectl -n "$ns" create secret tls "${name}-mtls" \
    --cert="$dir/${host}.pem" \
    --key="$dir/${host}-key.pem" \
    --dry-run=client -o yaml | kubectl apply -f -
}
