#!/usr/bin/env bash
# Produce/consume over the TLS listener with mutual TLS: encrypted channel, and
# identity taken from the client certificate (principal CN=mtls-client).
#   ./tls-demo.sh [topic]
set -euo pipefail
NS=kafka
TOPIC="${1:-demo}"

POD=$(kubectl -n "$NS" get pod -l strimzi.io/cluster=sanctum,strimzi.io/broker-role=true \
  -o jsonpath='{.items[0].metadata.name}')

# truststore = cluster CA (trust the broker); keystore = the client's cert+key (mTLS identity)
CA_P12=$(kubectl -n "$NS" get secret sanctum-cluster-ca-cert -o jsonpath='{.data.ca\.p12}')
CA_PW=$(kubectl -n "$NS" get secret sanctum-cluster-ca-cert -o jsonpath='{.data.ca\.password}' | base64 -d)
U_P12=$(kubectl -n "$NS" get secret mtls-client -o jsonpath='{.data.user\.p12}')
U_PW=$(kubectl -n "$NS" get secret mtls-client -o jsonpath='{.data.user\.password}' | base64 -d)

kubectl -n "$NS" exec -i "$POD" -- bash -s "$CA_P12" "$CA_PW" "$U_P12" "$U_PW" "$TOPIC" <<'REMOTE'
set -e
CA_P12="$1"; CA_PW="$2"; U_P12="$3"; U_PW="$4"; TOPIC="$5"
echo "$CA_P12" | base64 -d > /tmp/truststore.p12
echo "$U_P12"  | base64 -d > /tmp/keystore.p12
cat > /tmp/tls.props <<EOF
security.protocol=SSL
ssl.truststore.location=/tmp/truststore.p12
ssl.truststore.password=$CA_PW
ssl.truststore.type=PKCS12
ssl.keystore.location=/tmp/keystore.p12
ssl.keystore.password=$U_PW
ssl.keystore.type=PKCS12
EOF
echo "== producing over TLS :9093 (mutual TLS, identity = cert CN=mtls-client) =="
for i in 1 2 3; do echo "tls-$i"; done \
  | /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server sanctum-kafka-bootstrap:9093 \
      --topic "$TOPIC" --producer.config /tmp/tls.props
echo "== consuming over TLS :9093 =="
/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server sanctum-kafka-bootstrap:9093 --topic "$TOPIC" \
  --group tls-demo --from-beginning --max-messages 3 --timeout-ms 20000 --consumer.config /tmp/tls.props
REMOTE
echo "TLS/mTLS demo OK"
