#!/usr/bin/env bash
# STRICT mTLS: the web namespace only accepts mutual-TLS traffic. A client with a
# sidecar succeeds; a plaintext client (injection off) is rejected.
set -euo pipefail
NS=web

echo "== mTLS mode for the web namespace =="
kubectl -n "$NS" get peerauthentication default -o jsonpath='{.metadata.name}: {.spec.mtls.mode}{"\n"}'

echo "== meshed client (has an istio-proxy sidecar) -> web  (expect HTTP 200) =="
kubectl -n "$NS" exec deploy/mesh-client -- \
  curl -s -o /dev/null -w "  HTTP %{http_code}\n" --max-time 5 http://web:8080/ \
  || echo "  FAILED (unexpected)"

echo "== plaintext client (injection off) -> web  (expect rejection) =="
if kubectl -n "$NS" exec deploy/plain-client -- \
     curl -s -o /dev/null -w "  HTTP %{http_code}\n" --max-time 5 http://web:8080/; then
  echo "  (unexpected: plaintext got through)"
else
  echo "  rejected: STRICT mTLS reset the plaintext connection"
fi
echo "mtls demo OK"
