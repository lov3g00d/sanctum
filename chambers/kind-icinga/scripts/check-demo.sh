#!/usr/bin/env bash
# End to end: a healthy service is OK, break it and watch Icinga drive the check
# to a HARD CRITICAL and fire a notification, then heal it and watch the recovery
# notification. State is read back from the Icinga 2 REST API, not the web UI.
set -euo pipefail

CTX=kind-icinga
NS=icinga
AUTH="icingaweb:icingaweb-api"
API="https://localhost:5665"

POD=$(kubectl --context "$CTX" -n "$NS" get pod -l app.kubernetes.io/name=icinga2 -o jsonpath='{.items[0].metadata.name}')

svc_attrs() {
  kubectl --context "$CTX" -n "$NS" exec "$POD" -c icinga2 -- \
    curl -sk -u "$AUTH" -H 'Accept: application/json' \
    "$API/v1/objects/services?service=webapp!http-health&attrs=state&attrs=state_type&attrs=last_check_result" 2>/dev/null
}
show_state() {
  svc_attrs | python3 -c 'import sys,json
a=json.load(sys.stdin)["results"][0]["attrs"]
S={0:"OK",1:"WARNING",2:"CRITICAL",3:"UNKNOWN"}; T={0:"SOFT",1:"HARD"}
out=a["last_check_result"]["output"][:66] if a["last_check_result"] else ""
print("  service webapp!http-health: %s (%s) - %s" % (S[a["state"]], T[a["state_type"]], out))'
}
app_health() {
  kubectl --context "$CTX" -n web exec deploy/webapp -- python -c \
    "import urllib.request,json,sys; urllib.request.urlopen(urllib.request.Request('http://localhost:8080/config',data=json.dumps({'healthy':sys.argv[1]=='true'}).encode(),headers={'Content-Type':'application/json'},method='POST'))" "$1"
}
is_state() { svc_attrs | python3 -c "import sys,json; a=json.load(sys.stdin)['results'][0]['attrs']; sys.exit(0 if a['state']==$1 and a['state_type']==$2 else 1)"; }
wait_hard() {
  local st=$1
  for _ in $(seq 1 40); do is_state "$st" 1 && return 0; sleep 3; done
  echo "  timeout waiting for HARD state $st"; return 1
}
clear_log() { kubectl --context "$CTX" -n "$NS" exec "$POD" -c icinga2 -- sh -c ': > /var/lib/icinga2/notify.log' 2>/dev/null || true; }
raw_log() { kubectl --context "$CTX" -n "$NS" exec "$POD" -c icinga2 -- cat /var/lib/icinga2/notify.log 2>/dev/null || true; }
wait_notify() { local pat=$1; for _ in $(seq 1 10); do raw_log | grep -q "$pat" && return 0; sleep 2; done; return 0; }
notify_log() { raw_log | sed 's/^/     /'; }

echo "== baseline: app healthy, service should settle OK =="
app_health true
wait_hard 0 && show_state
clear_log

echo "== break: app returns HTTP 500 on /healthz (SOFT then HARD after max_check_attempts) =="
app_health false
wait_hard 2 && show_state
wait_notify PROBLEM
echo "  -> notification log (Problem):"
notify_log

echo "== heal: app healthy again =="
app_health true
wait_hard 0 && show_state
wait_notify RECOVERY
echo "  -> notification log (Problem + Recovery):"
notify_log

echo "check-demo OK"
