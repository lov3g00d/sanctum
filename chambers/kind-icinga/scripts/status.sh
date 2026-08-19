#!/usr/bin/env bash
# Print the current state of every monitored service, read from the Icinga 2 API.
set -euo pipefail

CTX=kind-icinga
NS=icinga
AUTH="icingaweb:icingaweb-api"

POD=$(kubectl --context "$CTX" -n "$NS" get pod -l app.kubernetes.io/name=icinga2 -o jsonpath='{.items[0].metadata.name}')

kubectl --context "$CTX" -n "$NS" exec "$POD" -c icinga2 -- \
  curl -sk -u "$AUTH" -H 'Accept: application/json' \
  'https://localhost:5665/v1/objects/services?attrs=state&attrs=state_type&attrs=last_check_result' \
  | python3 -c 'import sys,json
S={0:"OK",1:"WARNING",2:"CRITICAL",3:"UNKNOWN"}; T={0:"SOFT",1:"HARD"}
for r in json.load(sys.stdin)["results"]:
    a=r["attrs"]; out=a["last_check_result"]["output"][:60] if a["last_check_result"] else ""
    print("%-28s %-8s %-4s %s" % (r["name"], S[a["state"]], T[a["state_type"]], out))'
