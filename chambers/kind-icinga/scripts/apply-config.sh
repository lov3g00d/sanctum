#!/usr/bin/env bash
# Push the Icinga monitoring config (Host, Service, Notification) to Icinga 2 as
# a config package through the REST API. This is the scriptable, GitOps-friendly
# way to manage Icinga 2 config when conf.d is disabled (as the chart ships it).
set -euo pipefail

CTX=kind-icinga
NS=icinga
AUTH="icingaweb:icingaweb-api"
PKG=webapp
API="https://localhost:5665"
CONF="$(cd "$(dirname "$0")/.." && pwd)/icinga/monitoring.conf"

POD=$(kubectl --context "$CTX" -n "$NS" get pod -l app.kubernetes.io/name=icinga2 -o jsonpath='{.items[0].metadata.name}')

api() {
  kubectl --context "$CTX" -n "$NS" exec -i "$POD" -c icinga2 -- \
    curl -sk -u "$AUTH" -H 'Accept: application/json' "$@"
}

if ! api "$API/v1/config/packages" | grep -q "\"name\":\"$PKG\""; then
  echo "creating config package '$PKG'"
  api -X POST "$API/v1/config/packages/$PKG" >/dev/null
fi

echo "deploying config stage"
python3 -c 'import json,sys; json.dump({"files":{"conf.d/monitoring.conf":open(sys.argv[1]).read()}}, sys.stdout)' "$CONF" \
  | api -H 'Content-Type: application/json' -X POST "$API/v1/config/stages/$PKG" --data-binary @- \
  | python3 -c 'import sys,json; r=json.load(sys.stdin)["results"][0]; print("  "+r["status"])'
