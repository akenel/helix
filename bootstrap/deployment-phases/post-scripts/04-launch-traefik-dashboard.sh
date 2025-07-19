#!/bin/bash

# --- Configuration ---
TRAEFIK_NAMESPACE="kube-system"
LOCAL_PORT="9000"
TRAEFIK_DASHBOARD_PORT="9000"
DASHBOARD_URL="http://localhost:${LOCAL_PORT}/dashboard/"

# --- Find the Traefik pod ---
TRAEFIK_POD=$(kubectl -n "${TRAEFIK_NAMESPACE}" get pods --selector "app.kubernetes.io/name=traefik" --output=name)

if [ -z "${TRAEFIK_POD}" ]; then
  echo "Error: Could not find Traefik pod in namespace ${TRAEFIK_NAMESPACE}. Is Traefik deployed?"
  # Instead of exiting, you might want to return an error code or just log and continue
  # For this specific integration, it might be better to let the calling script handle the exit.
  exit 1
fi

echo "Found Traefik pod: ${TRAEFIK_POD}"

# --- Start Port Forwarding in the background ---
echo "Starting port-forward from ${TRAEFIK_POD} ${TRAEFIK_DASHBOARD_PORT} to localhost:${LOCAL_PORT} (in background)..."
# The '&' sends the command to the background.
# 'sleep 1' gives a moment for the port-forward to establish before opening the browser.
# !!! IMPORTANT: We are NOT using 'wait' or 'trap' for the port-forward in this version
# because the calling script will continue immediately.
kubectl -n "${TRAEFIK_NAMESPACE}" port-forward "${TRAEFIK_POD}" "${LOCAL_PORT}:${TRAEFIK_DASHBOARD_PORT}" &
PORT_FORWARD_PID=$! # Store PID for potential manual cleanup later

sleep 2 # Give it a bit more time to ensure the connection is stable

# --- Open the Web Browser ---
echo "Opening Traefik dashboard in your web browser at ${DASHBOARD_URL}..."

if command -v xdg-open &> /dev/null; then
    xdg-open "${DASHBOARD_URL}" & # Open browser in background too, to not block the script
elif command -v open &> /dev/null; then # For macOS
    open "${DASHBOARD_URL}" &
elif command -v start &> /dev/null; then # For Windows (via Git Bash/WSL if start is aliased)
    start "${DASHBOARD_URL}" &
elif command -v powershell.exe &> /dev/null; then # For Windows (direct PowerShell)
    powershell.exe -Command "Start-Process '${DASHBOARD_URL}'" &
else
    echo "Could not find a command to open the web browser automatically."
    echo "Please open your browser manually and navigate to: ${DASHBOARD_URL}"
fi

# IMPORTANT NOTE: The port-forwarding process (kubectl) will now be a background process
# that is NOT directly managed by this script after it exits.
# You will need to manually kill it later using its PID or by finding the process.
# For example: ps aux | grep "kubectl port-forward"
# Or: kill <PORT_FORWARD_PID> (if you keep track of it in the parent script)
echo "Traefik dashboard should now be open in your browser."
echo "The port-forwarding (PID: ${PORT_FORWARD_PID}) is running in the background."
echo "You will need to manually kill this process later (e.g., 'kill ${PORT_FORWARD_PID}') or when you are done with the dashboard."

# The script exits here, allowing the calling script to continue.
# The port-forwarding process remains active in the background.