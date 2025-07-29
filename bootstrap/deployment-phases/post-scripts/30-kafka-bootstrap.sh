#!/bin/bash
# 🧱 bootstrap\30-kafka-bootstrap.sh
set -e
echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
echo "🚀 Kafka to build real-time pipelines    🧱"
echo "✨━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━✨"
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.helix/kubeconfig.yaml}"
export KUBECONFIG="$KUBECONFIG_PATH"
kubectl config use-context helix >/dev/null 2>&1 || {
  echo "❌ Unable to connect to Kubernetes API. Check kubeconfig or cluster status."
  exit 1
}
start_kafka_spinner() {
  local frames=("🪇    " " 🪇   " "  🪇  " "   🪇 " "    🪇" "   🪇 " "  🪇  " " 🪇   " "🪇    ")
  local i=0
  while true; do
    printf "\r🔄 Setting up Kafka... %s" "${frames[i]}"
    i=$(( (i + 1) % ${#frames[@]} ))
    sleep 0.4
  done
}

####### Prompt for cluster ############
echo "🚀 quick k3d cluster refresh before Kafka deployment... "
k3d cluster stop helix
k3d cluster start helix
echo "🔍 Available k3d clusters:"
k3d cluster list | awk 'NR>1 {print "🔥 " $1}'
echo ""

echo ""
if [ -t 0 ]; then
  read -t 10 -p "🌠 Enter cluster name [default: helix]: " CLUSTER_INPUT || true
fi

CLUSTER=${CLUSTER_INPUT:-helix}

echo "📌 Using cluster: $CLUSTER" 
DOMAIN=$CLUSTER # Assuming DOMAIN is always "helix" regardless of cluster name
NAMESPACE="kafka"
RELEASE="kafka-${CLUSTER}"
CHART="bitnami/kafka"

echo "🎡 Updating Repos ..."
start_kafka_spinner & SPINNER_PID=$!
helm repo update

kill "$SPINNER_PID" >/dev/null 2>&1 || true
wait "$SPINNER_PID" 2>/dev/null || true
echo ""

# 🔄 If You’re Reinstalling Often
# Keep persistence disabled unless you're specifically testing Kafka durability or recovery.
# For development, quick testing, or automation flows (e.g. CI/CD), ephemeral setups are simpler.
# Optional: enable persistence for testing

cat <<EOF >configs/kafka/kafka-deploy-values.yaml
replicaCount: 1

zookeeper:
  enabled: true
  replicaCount: 1

listeners:
  client:
    protocol: SASL_PLAINTEXT
  interbroker:
    protocol: SASL_PLAINTEXT
  external:
    protocol: SASL_PLAINTEXT

externalAccess:
  enabled: true
  autoDiscovery:
    enabled: true
  service:
    type: ClusterIP
    domain: helix

service:
  type: ClusterIP

rbac:
  create: true

auth:
  enabled: true
  sasl:
    mechanism: plain
  clientProtocol: sasl
  interBrokerProtocol: sasl
  zookeeperProtocol: sasl
  username: kafkauser
  password: kafkapass
  existingSecret: ""
  allowAnonymous: false

metrics:
  kafka:
    enabled: true
  jmx:
    enabled: true

persistence:
  storageClass: "local-path" 

EOF

echo "📦 HELM upgrade --install Kafka Repo ..."
echo ""
start_kafka_spinner & SPINNER_PID=$!

helm upgrade --install "$RELEASE"  "$CHART" \
    --version 19.1.2 \
    --namespace "$NAMESPACE" \
    --create-namespace \
    -f configs/kafka/kafka-deploy-values.yaml || \
    { echo "❌ Kafka helm install failed"; exit 1; }

####### Kafka Deployed #########
# rm -f configs/kafka/kafka-deploy-values.yaml
echo ""
kill "$SPINNER_PID" >/dev/null 2>&1 || true
wait "$SPINNER_PID" 2>/dev/null || true
echo -e "\r${BRIGHT_GREEN}✅ Kafka installed successfully!${NC}"
####### Kafka Credentials #########
echo "📡 Kafka deployed:"