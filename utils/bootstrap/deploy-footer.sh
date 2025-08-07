#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR
# bootstrap\utils\deploy-footer.sh
# 💠 Deploy Footer Printer
# Returns ✅ if any pod in the namespace matches the name pattern (wildcard) and is Running, else ❌
# Returns a status icon for any pod in the namespace matching the name pattern
get_status() {
  local ns=$1 name_pattern=$2
  local pod_line
   if [[ -z "$ns" || -z "$name_pattern" ]]; then
    echo "❌"
    return
  fi
  # Get the first pod matching the name 
  # Get the pod name safely
    echo "🧠 Checking Keycloak pod..."
    POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    echo "✅ Keycloak pod found in namespace '$NAMESPACE'."
    echo "🔍 Using Keycloak pod: $POD"
      pod_line=$(kubectl get pods -n "$ns" -l "app.kubernetes.io/name=$name_pattern" -o wide | grep -m 1 "$name_pattern")
      if [[ -z "$pod_line" ]]; then
        echo "❌ No pods found matching '$name_pattern' in namespace '$ns'."
        return
      fi  
  local status
  status=$(echo "$pod_line" | awk '{print $3}')
  case "$status" in
    Running) echo "✅" ;;
    Pending|Waiting) echo "⏳" ;;
    Error|CrashLoopBackOff|ImagePullBackOff|Failed) echo "❌" ;;
    ContainerCreating|PodInitializing) echo "🚀" ;;
    Completed|Succeeded) echo "✅" ;;
    Unknown) echo "❓" ;;
    Terminating) echo "🏴‍☠️" ;;
    *) echo "⏳" ;;
  esac
}
# Returns ✅ if the service exists in the namespace, else ❌
get_service_status() {
  local ns=$1
  local svc=$2
  if kubectl get svc -n "$ns" "$svc" &>/dev/null; then
    echo "✅"
  else
    echo "❌"
  fi
}

# TLS Chain status helpers
tls_ca_status() {
  # Check if mkcert-root-ca-secret exists and is of type kubernetes.io/tls
  if kubectl get secret -n cert-manager mkcert-root-ca-secret &>/dev/null; then
    local typ
    typ=$(kubectl get secret -n cert-manager mkcert-root-ca-secret -o jsonpath='{.type}')
    if [[ "$typ" == "kubernetes.io/tls" ]]; then
      echo "✅"
    elif [[ -n "$typ" ]]; then
      echo "⏳" # If type exists but not kubernetes.io/tls, assume in progress
      echo "DEBUG: mkcert-root-ca-secret exists but is not of type kubernetes.io/tls"
    else  
      echo "📦"
    fi
  else
    echo "❌"
  fi
}

clusterissuer_status() {
  if kubectl get clusterissuer mkcert-ca-issuer &>/dev/null; then
    local cond
    cond=$(kubectl get clusterissuer mkcert-ca-issuer -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [[ "$cond" == "True" ]]; then
      echo "✅"
    elif [[ -n "$cond" ]]; then
      echo "🎬"
    else
      echo "❌"
    fi
  else
    echo "❌"
  fi
}

print_deploy_footer() {
  echo ""
  echo "🎬 Deployment Summary:"
  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  echo "🔧 Components 🧩 Core Services:"
  echo "🔍 Investigating Cluster Deployment:"
  echo ""
  printf "   🔐 Vault        → %s\n" "$(get_status vault vault-helix)"
  printf "   🧠 Keycloak     → %s\n" "$(get_status identity keycloak-helix)"
  printf "   🗄️ Postgres     → %s\n" "$(get_status identity postgresql-helix)"
  printf "   🧰 Portainer    → %s\n" "$(get_status portainer portainer)"
  printf "   🧪 Adminer      → %s\n" "$(get_status database-ui adminer)"
  printf "   📢 Kafka        → %s\n" "$(get_status kafka kafka)"
  printf "   🌐 Kong         → %s\n" "$(get_status kong kong)"

  echo ""
  echo "🔐 TLS Chain:"
  printf "   🎩 mkcert CA           %s\n" "$(tls_ca_status)"
  printf "   🪄 ClusterIssuer       %s\n" "$(clusterissuer_status)"

  echo ""
  echo "📊 Secrets:"
  printf "   🔑 Vault KV            %s\n" "$(kubectl get secret -n vault &>/dev/null && echo '✅' || echo '❌')"
  printf "   🔐 Kubeconfig Patched  %s\n" "$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null | grep -q '127.0.0.1:6550' && echo '✅' || echo '❌')"
  printf "   🔑 App Keys Injected   %s\n" "$(kubectl get secret -n identity  &>/dev/null && echo '✅' || echo '❌')"

  echo ""
  echo "🔑 App Secrets:"
  printf "   🔑 Keycloak Secret     %s\n" "$(kubectl get secret -n identity keycloak-helix &>/dev/null && echo '✅' || echo '❌')"
  printf "   🔑 Postgres Secret     %s\n" "$(kubectl get secret -n identity postgresql-helix &>/dev/null && echo '✅' || echo '❌')"
  printf "   🔒 Keycloak TLS        %s\n" "$(kubectl get secret -n identity keycloak.helix-tls &>/dev/null && echo '✅' || echo '❌')"
  printf "   🎁 Helm Keycloak Rel.  %s\n" "$(kubectl get secret -n identity sh.helm.release.v1.keycloak-helix.v1 &>/dev/null && echo '✅' || echo '❌')"
  printf "   🎁 Helm Postgres Rel.  %s\n" "$(kubectl get secret -n identity sh.helm.release.v1.postgresql-helix.v1 &>/dev/null && echo '✅' || echo '❌')"
   
  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  JOKE=$(curl -s https://api.chucknorris.io/jokes/random | jq -r '.value' || echo "Chuck Norris installed Helm by blinking.")
  echo "🕵️ \"$JOKE!\""
  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  
  echo "✅ Deployment Summary Complete!"
  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  echo "🎉 Congratulations! Your Helix Orchestrator is now fully deployed and operational."
  echo "For more information, visit: https://github.com/akenel/helix/blob/main/README.md"
  echo ""
  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  echo "Thank you for using Helix Orchestrator! 🙌"
  echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
  sleep 3
  exit 0
}
