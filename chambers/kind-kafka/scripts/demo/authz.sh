#!/usr/bin/env bash
# Show ACL enforcement: each user can do only what its ACLs grant.
set -uo pipefail
NS=kafka
POD=$(kubectl -n "$NS" get pod -l strimzi.io/cluster=sanctum,strimzi.io/broker-role=true \
  -o jsonpath='{.items[0].metadata.name}')

# write a SASL client config for a user into the pod
writeprops() {
  local u="$1" pw
  pw=$(kubectl -n "$NS" get secret "$u" -o jsonpath='{.data.password}' | base64 -d)
  kubectl -n "$NS" exec -i "$POD" -- bash -c "cat > /tmp/$u.props" <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="$u" password="$pw";
EOF
}
writeprops producer
writeprops consumer

# check DESC EXPECT(ALLOW|DENY) POD-COMMAND
check() {
  local desc="$1" expect="$2"; shift 2
  local out ec result mark
  out=$(kubectl -n "$NS" exec -i "$POD" -- bash -c "$*" 2>&1); ec=$?
  if echo "$out" | grep -qiE 'not authorized|AuthorizationException|authentication failed|SaslAuthenticationException|TimeoutException|metadata update after close|disconnected'; then
    result=DENY
  elif [ "$ec" -eq 0 ]; then result=ALLOW; else result=DENY; fi
  mark="FAIL"; [ "$result" = "$expect" ] && mark="ok"
  printf "  [%-4s] %-48s expected=%-5s got=%s\n" "$mark" "$desc" "$expect" "$result"
}

P='/tmp/producer.props'
C='/tmp/consumer.props'
BS='--bootstrap-server localhost:9092'
KP=/opt/kafka/bin/kafka-console-producer.sh
KC=/opt/kafka/bin/kafka-console-consumer.sh

echo "== producer: may WRITE demo, nothing else =="
check "produce to demo"        ALLOW "echo hi | $KP $BS --topic demo --producer.config $P"
check "consume demo (no Read)"  DENY "$KC $BS --topic demo --group app --from-beginning --max-messages 1 --timeout-ms 8000 --consumer.config $P"

echo "== consumer: may READ demo, nothing else =="
check "consume demo"           ALLOW "$KC $BS --topic demo --group app --from-beginning --max-messages 1 --timeout-ms 8000 --consumer.config $C"
check "produce to demo (no Write)" DENY "echo hi | $KP $BS --topic demo --producer.config $C"

echo "== no credentials at all =="
check "produce with no auth"    DENY "echo hi | timeout 20 $KP $BS --topic demo"
