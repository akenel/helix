#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR

set -e

NAMESPACE_LIST=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}')
LOGFILE="https_check_report.log"
> $LOGFILE

echo "🔍 Starting HTTPS checks..." | tee -a $LOGFILE

# Modify this domain template based on your Ingress setup
BASE_DOMAIN="example.local"

for ns in $NAMESPACE_LIST; do
  echo "🗂️  Checking namespace: $ns" | tee -a $LOGFILE
  
  SERVICES=$(kubectl get ingress -n $ns -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.rules[*].host}{"\n"}{end}')

  if [ -z "$SERVICES" ]; then
    echo "   ➤ No Ingress resources found." | tee -a $LOGFILE
    continue
  fi

  while read -r line; do
    NAME=$(echo $line | awk '{print $1}')
    HOST=$(echo $line | awk '{print $2}')
    
    echo -n "   ➤ Checking $HOST... " | tee -a $LOGFILE
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --resolve "$HOST:443:127.0.0.1" https://$HOST)

    # Treat 200, 301, 302, 307, 308 as OK
    if [[ "$HTTP_CODE" =~ ^(200|301|302|307|308)$ ]]; then
      if [[ "$HTTP_CODE" == "200" ]]; then
        echo "✅ HTTPS OK" | tee -a $LOGFILE
      else
        echo "✅ HTTPS Redirect (HTTP code $HTTP_CODE)" | tee -a $LOGFILE
      fi
    else
      echo "❌ FAILED (HTTP code $HTTP_CODE)" | tee -a $LOGFILE
    fi
  done <<< "$SERVICES"
done

echo "✅ Done. Full report saved in $LOGFILE"
