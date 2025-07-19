#!/bin/bash
NODE_NAME=$(k3d node list | grep server | awk '{print $1}')

echo "🔍 Checking Keycloak volume mounts inside $NODE_NAME..."

k3d node shell "$NODE_NAME" -- bash -c '
  echo -e "\n📁 /helix-assets/helix-theme/login:"
  ls -l /helix-assets/helix-theme/login

  echo -e "\n📁 /keycloak-configs:"
  ls -l /keycloak-configs
'
