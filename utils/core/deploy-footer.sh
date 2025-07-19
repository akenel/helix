#!/bin/bash
# bootstrap\utils\deploy-footer.sh
# 💠 Deploy Footer Printer
print_deploy_footer() {
  echo ""
  echo "🎬 Deployment Summary:"
  echo "📦 Services:"
  printf "   🟢 Vault     %s\n"     "${VAULT_STATUS:-⏳}"
  printf "   🟢 Portainer %s\n"     "${PORTAINER_STATUS:-⏳}"
  printf "   🟢 Postgres  %s\n"     "${POSTGRES_STATUS:-⏳}"
  printf "   🟢 Keycloak  %s\n"     "${KEYCLOAK_STATUS:-⏳}"
  printf "   🟢 Adminer   %s\n"     "${DATABASE_UI_STATUS:-⏳}"
  printf "   🟢 Kafka     %s\n"     "${KAFKA_STATUS:-⏳}"
  printf "   🟢 Kong      %s\n"     "${KONG_STATUS:-⏳}"
  echo ""
  echo "🔐 TLS Chain:"
  printf "   🔐 mkcert CA           %s\n" "${TLSCASTATUS:-⏳}"
  printf "   🔐 ClusterIssuer       %s\n" "${CLUSTERISSUERSTATUS:-⏳}"
  printf "   🔐 Kubeconfig Patched  %s\n" "${KUBECONFIG_PATCHED:-⏳}"
  echo ""
  echo "📊 Secrets:"
  printf "   🔑 Vault KV            %s\n" "${VAULTKVSTATUS:-⏳}"
  printf "   🔑 App Keys Injected   %s\n" "${APPSECRETSSTATUS:-⏳}"
  echo ""
}

# - ⏳ = in progress
# - ✅ = success
# - ❌ = failed
# - 🔒 = not started