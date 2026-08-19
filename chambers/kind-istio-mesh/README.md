# Chamber: kind-istio-mesh

Istio service mesh on kind: a web app deployed as v1 and v2, with weighted
routing for canary and blue-green releases, and STRICT mutual TLS. Practice the
traffic management and workload security a service mesh gives you without
touching application code.

## Stack

kind + Istio, installed from the official Helm charts (`base`, `istiod`, and the
ingress `gateway`). The web app (Flask, returns its own version) runs as two
Deployments, `v1` and `v2`, behind one Service. A `DestinationRule` defines the
subsets, a `VirtualService` splits traffic between them by weight, and a
`Gateway` exposes the app on the ingress gateway. A `PeerAuthentication` enforces
STRICT mTLS across the namespace.

## Prerequisites

`nix develop` from the repo root (provides `kind`, `kubectl`, `helm`, `task`,
`jq`, `curl`) and a running Docker.

## Use

```sh
cd chambers/kind-istio-mesh
task up          # kind + Istio + app + routing + mTLS
task status      # current traffic split and sidecar count
task canary      # shift v1 -> v2 gradually (90/10, 50/50, 0/100)
task bluegreen   # flip v1 -> v2 in one step, then roll back
task mtls-demo   # STRICT mTLS accepts a meshed client, rejects a plaintext one
task fault       # inject faults (Istio returns errors without calling the app)
task resilience  # route timeouts and retries masking transient failures
task circuit     # circuit breaking: a tight connection pool sheds load with 503
task mirror      # mirror live traffic to v2 while users still get v1
task reset       # route 100% back to v1
task down        # delete the kind cluster
```

Ingress: http://localhost:18081/ (curl it repeatedly to watch which version
answers as you change the weights).

## What it demonstrates

- **Sidecar injection**: each app pod runs an `istio-proxy` beside the container
  (the pod shows `2/2`), and all traffic flows through it.
- **Canary**: route a small percentage to a new version, watch it, then ramp up.
- **Blue-green**: cut the whole fleet over at once and roll back instantly.
- **L7 routing**: `VirtualService` weights over `DestinationRule` subsets,
  exposed through a `Gateway`, all as data-plane config the app never sees.
- **Zero-trust mTLS**: STRICT `PeerAuthentication` means workloads only accept
  mutual-TLS from other sidecars; a plaintext client is rejected by the mesh.
- **Resilience and testing in the mesh**: fault injection, route timeouts and
  retries, circuit breaking (connection-pool shedding), and traffic mirroring,
  all as `VirtualService`/`DestinationRule` config the app never sees.

## Reference

[`istio.md`](istio.md) is a deep-dive on how Istio works end to end (data plane
vs control plane, sidecar injection, the request path, the config CRDs, mTLS,
xDS), grounded in this chamber.
