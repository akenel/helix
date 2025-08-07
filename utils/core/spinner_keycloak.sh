#!/bin/bash
# ────────────────────────────────────────────────
# ☕ Spinner: Wait for Keycloak to become Ready
# utils\core\spinner_keycloak.sh
# ────────────────────────────────────────────────

SPINNER_PID=""
cleanup_spinner() {
  [[ -n "$SPINNER_PID" ]] && kill "$SPINNER_PID" 2>/dev/null || true
  stop_spinner 1
}
trap cleanup_spinner SIGINT SIGTERM ERR EXIT

start_spinner "☕ Waiting for Keycloak pod to become Ready..."

# Wait for Keycloak to reach READY 1/1
while true; do
  status=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$KEYCLOAK_RELEASE" \
    -o jsonpath="{.items[0].status.containerStatuses[0].ready}" 2>/dev/null || echo "false")

  [[ "$status" == "true" ]] && break
  sleep 5
done

stop_spinner 0
trap - SIGINT SIGTERM ERR EXIT
