#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR
# bootstrap/70-cert-status-summary.sh
# 🔧 Generate a summary of Helix TLS certificates

CERT_DIR="./certs"
SUMMARY_FILE="$CERT_DIR/helix-cert-summary.txt"
DATE=$(date "+%Y-%m-%d %H:%M:%S")

mkdir -p "$CERT_DIR"  # Ensure directory exists

echo "📋 Helix Certificate Summary - $DATE" > "$SUMMARY_FILE"
echo "📂 Certificates found in: $CERT_DIR" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# 📄 List of files in cert directory
echo "🗃️ Directory Listing:" >> "$SUMMARY_FILE"
ls -lh "$CERT_DIR" | awk 'NR==1{print "   " $0} NR>1{print "   ├─ " $9 "\t" $5 "\t" $6 " " $7 " " $8}' >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# 🧩 Helper: Describe each known service
describe_cert() {
  local name=$1
  local url=$2
  if [[ -f "$CERT_DIR/$name.crt" ]]; then
    echo "🔐 $name.helix" >> "$SUMMARY_FILE"
    echo "   ├─ 📄 Certificate: $name.crt" >> "$SUMMARY_FILE"
    echo "   ├─ 🔑 Key file:    $name.key" >> "$SUMMARY_FILE"
    echo "   ├─ 🌐 URL:         https://$url" >> "$SUMMARY_FILE"
    echo "   └─ 📎 Usage:       Access dashboard for $name" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
  fi
}

# 🔍 Scan for known certs
describe_cert "keycloak" "keycloak.helix"
describe_cert "portainer" "portainer.helix:3369"
describe_cert "vault" "vault.helix"
describe_cert "adminer" "adminer.helix:8080"
describe_cert "traefik" "traefik.helix/dashboard"

# 🧾 Host file info
{
echo "📌 Host File Reminder (manual update required once):"
echo "   Add these lines to your system host file:"
echo "   127.0.0.1   keycloak.helix"
echo "   127.0.0.1   portainer.helix"
echo "   127.0.0.1   vault.helix"
echo "   127.0.0.1   adminer.helix"
echo "   127.0.0.1   traefik.helix"
echo ""
} >> "$SUMMARY_FILE"

# 🛠️ Cert install instructions
{
echo "📥 Certificate Installation Instructions:"
echo "   1. Open the cert file (e.g. keycloak.helix.crt)"
echo "   2. Right-click → Install Certificate → Local Machine → Trusted Root Certification Authorities"
echo "   3. Accept the prompt if admin elevation is requested"
echo ""
} >> "$SUMMARY_FILE"

echo "✅ Certificate summary generated at: $SUMMARY_FILE"
echo ""

# 📤 Output the summary to the console
cat "$SUMMARY_FILE"
