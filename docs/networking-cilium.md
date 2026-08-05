# Cilium: the eBPF dataplane for Nimbus

Nimbus runs Cilium as the primary CNI on EKS. This replaces the packet path that a
default cluster gets from the AWS VPC CNI plus kube-proxy with a single eBPF
dataplane, and it is the reason the platform can express L7 network policy and see
every flow without a service mesh sidecar. This doc explains what Cilium buys us,
the specific EKS install choice (replace, not chain), the bootstrap ordering that a
kube-proxy-free cluster forces, and how Hubble and CiliumNetworkPolicy fit the rest
of the repo.

## Why Cilium

A stock EKS cluster forwards packets with two moving parts: the VPC CNI (aws-node)
wires pod ENIs and IPs, and kube-proxy programs iptables rules for every Service so
ClusterIP traffic reaches a backend pod. Both are fine until they are not. iptables
Service handling degrades as rule count grows, network policy stops at L3/L4, and you
have no built-in view of what is actually talking to what.

Cilium moves forwarding, load-balancing, and policy into eBPF programs attached at
the socket and tc layers. That gives us three things the default stack cannot:

- **kube-proxy replacement.** Cilium implements Service load-balancing in eBPF, so
  kube-proxy is removed entirely. Lookups are hash-table based rather than a linear
  iptables chain, which matters once a cluster has many Services.
- **L3-L7 policy.** CiliumNetworkPolicy filters on HTTP method and path, DNS names,
  and Kubernetes identity, not just IP and port. The example in
  `charts/podinfo/templates/ciliumnetworkpolicy.yaml` allows `GET /metrics` from monitoring while
  denying every other verb and path, which a Kubernetes NetworkPolicy cannot do.
- **Hubble observability.** Because the dataplane already parses flows, Hubble
  exports them as a live service map and as Prometheus metrics with no sidecars.

## The EKS choice: replace, not chain

On EKS, Cilium can run two ways. In **chaining** mode it sits behind the AWS VPC CNI
and only adds policy and observability; aws-node keeps owning IPAM and forwarding. In
**replace** mode Cilium owns the dataplane and Service load-balancing outright. Nimbus
picks replace, in ENI IPAM mode.

ENI mode means Cilium still hands each pod a routable VPC IP from an ENI, exactly like
the VPC CNI does, so pod addresses remain first-class in the VPC and the ALB can target
them directly. What changes is who forwards the packet: Cilium does, in eBPF, with
`routingMode: native` and masquerading on `eth0`. The AWS VPC CNI daemonset stays
installed because ENI mode still leans on it for ENI and IP allocation, but its routing
half is switched off (see the aws-node patch below). We take replace over chain because
the whole point is the eBPF dataplane and kube-proxy removal; chaining would keep the
iptables Service path we are trying to retire.

The Helm values that encode this (`terraform/modules/platform/cilium.tf`):

```yaml
eni:
  enabled: true
ipam:
  mode: eni
egressMasqueradeInterfaces: eth0
routingMode: native
kubeProxyReplacement: true
k8sServiceHost: <cluster API endpoint, no scheme>
k8sServicePort: 443
```

`k8sServiceHost` and `k8sServicePort` are not optional here. With kube-proxy gone, the
Cilium agent cannot reach the API server through the `kubernetes` ClusterIP Service,
because nothing is programming that Service yet. It needs the real control-plane
endpoint to bootstrap, which is why the Terraform derives it from the EKS cluster
endpoint.

## Bootstrap ordering

A kube-proxy-free cluster has a chicken-and-egg window: nodes join before Cilium is
running, and any pod that starts in that window comes up with no working dataplane. The
platform handles this with a taint and a defined install order.

1. **Cluster comes up kube-proxy-free.** The EKS module (`terraform/modules/eks/main.tf`)
   runs on terraform-aws-modules/eks v21, which hardcodes
   `bootstrap_self_managed_addons = false`. EKS therefore installs no networking addon
   unless it is declared. We declare `coredns`, `vpc-cni`, and `eks-pod-identity-agent`,
   and deliberately omit `kube-proxy`. It is absent because it is never requested.
2. **Nodes carry the not-ready taint.** The managed node group seeds every node with
   `node.cilium.io/agent-not-ready=true:NoExecute`. This is the same taint Cilium sets
   itself, and it keeps all workloads off a node until the Cilium agent is Ready and has
   claimed the dataplane. Without it, pods would schedule onto a node whose networking is
   not yet owned by anyone.
3. **Cilium installs.** The Helm release lands in `kube-system`, the agent starts on each
   node, programs eBPF, and removes the not-ready taint once it is Ready.
4. **aws-node is patched off.** The VPC CNI dataplane is neutralized so it does not fight
   Cilium for forwarding, while its IPAM stays available:

   ```bash
   kubectl -n kube-system patch daemonset aws-node --type=strategic \
     -p '{"spec":{"template":{"spec":{"nodeSelector":{"io.cilium/aws-node-enabled":"true"}}}}}'
   ```

   No node carries the `io.cilium/aws-node-enabled=true` label, so aws-node schedules
   onto zero nodes and Cilium owns the packet path. This is a day-0 runtime step, not
   Terraform state, so it lives here in the runbook rather than in the module.
5. **Workloads schedule.** With Cilium Ready and the taint cleared, CoreDNS, the platform
   controllers, and podinfo come up on a working eBPF dataplane.

## Hubble: UI and metrics into Prometheus

Hubble ships with the same release: `hubble.relay.enabled` aggregates per-node flow data,
and `hubble.ui.enabled` serves the service map and flow inspector. The UI is an internal
debugging tool; reach it with `cilium hubble ui` or a port-forward rather than exposing it.

For long-term signal, `hubble.metrics.enabled` turns on the `dns`, `drop`, `tcp`, `flow`,
and `http` metric families, and `hubble.metrics.serviceMonitor.enabled` creates a
ServiceMonitor so the repo's kube-prometheus-stack scrapes them. One caveat: the
ServiceMonitor's labels and namespace must fall inside the Prometheus instance's selector
(kube-prometheus-stack scopes what it scrapes), otherwise the target is defined but never
picked up. Once scraped, the flow, drop, and DNS metrics drive Grafana dashboards and
alerts, for example alerting on a rising `hubble_drop_total` for the nimbus namespace.

## How CiliumNetworkPolicy relates to the existing NetworkPolicies

The repo already ships Kubernetes NetworkPolicies in
`terraform/modules/platform/policies/cluster/networkpolicy.yaml`: default-deny, allow DNS egress, allow ingress to
podinfo, allow egress to the data stores. Cilium enforces those natively; adopting it does
not orphan them. `charts/podinfo/templates/ciliumnetworkpolicy.yaml` layers on top rather than replacing them.

The division of labour is by protocol layer. The Kubernetes policies handle L3/L4: which
CIDRs and namespaces may reach podinfo on 9898, which ports egress may use. The
CiliumNetworkPolicy adds L7 on the same identity: of the traffic already permitted to reach
podinfo, only `GET` on `/`, `/healthz`, `/readyz`, and `/metrics` is allowed through, with
`/metrics` restricted to the monitoring namespace. A CiliumNetworkPolicy whose endpoint
selector appears in both an ingress and an egress section is default-deny in both
directions, so the L7 policy is self-contained: it denies everything for podinfo except the
flows it names, and it keeps DNS egress open so name resolution still works. The two policy
kinds compose; an allow requires passing both.
