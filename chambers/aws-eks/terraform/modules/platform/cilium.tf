# Cilium is the primary CNI and dataplane. It runs in EKS ENI mode (pods get
# routable VPC IPs from ENIs, same as the AWS VPC CNI) but replaces the packet
# path with eBPF and takes over Service load-balancing so the cluster runs
# without kube-proxy. That buys L3-L7 network policy (CiliumNetworkPolicy) and
# Hubble flow observability that iptables-based kube-proxy cannot.
#
# In ENI mode the AWS VPC CNI (aws-node) still handles ENI/IP allocation, but its
# routing dataplane is neutralized at install time with a one-off
#   kubectl -n kube-system patch daemonset aws-node --type=strategic \
#     -p '{"spec":{"template":{"spec":{"nodeSelector":{"io.cilium/aws-node-enabled":"true"}}}}}'
# so aws-node schedules nowhere and Cilium owns forwarding. That patch is a day-0
# runtime step, not Terraform state; it is documented in docs/networking-cilium.md.
resource "helm_release" "cilium" {
  count      = var.enable_cilium ? 1 : 0
  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.cilium_chart_version

  atomic = true
  wait   = true

  values = [
    yamlencode({
      eni = {
        enabled = true
      }
      ipam = {
        mode = "eni"
      }
      egressMasqueradeInterfaces = "eth0"
      routingMode                = "native"

      kubeProxyReplacement = true
      # kube-proxy is gone, so the agent cannot reach the API server through a
      # ClusterIP Service. It needs the real control-plane endpoint to bootstrap.
      k8sServiceHost = replace(data.aws_eks_cluster.this.endpoint, "https://", "")
      k8sServicePort = 443

      hubble = {
        enabled = true
        relay = {
          enabled = true
        }
        ui = {
          enabled = true
        }
        metrics = {
          enabled = ["dns", "drop", "tcp", "flow", "http"]
          serviceMonitor = {
            enabled = true
          }
        }
      }
    })
  ]
}
