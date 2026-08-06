# The EC2NodeClass and NodePool are the day-2 tuning karpenter.tf deliberately leaves out:
# they tell Karpenter what AWS resources to launch (the node class) and what shapes to pick
# from (the pool). They are Kubernetes custom resources of the Karpenter CRDs, so they are
# applied via kubectl_manifest after the controller (and its CRDs) are installed.
resource "kubectl_manifest" "karpenter_node_class" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      amiSelectorTerms = [{ alias = "al2023@latest" }]
      role             = module.karpenter[0].node_iam_role_name

      subnetSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = var.cluster_name }
      }]
      securityGroupSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = var.cluster_name }
      }]

      metadataOptions = {
        httpTokens              = "required"
        httpPutResponseHopLimit = 1
      }

      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize = "20Gi"
          volumeType = "gp3"
          encrypted  = true
        }
      }]

      tags = local.common_tags
    }
  })

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "karpenter_node_pool" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "default"
    }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }

          # This cluster is kube-proxy-free and Cilium owns the dataplane, so a node has no
          # working networking until its Cilium agent is Ready. Seeding the same startup
          # taint Cilium uses keeps workloads off Karpenter-provisioned nodes until Cilium
          # removes it, mirroring the managed node group in the eks module.
          startupTaints = [{
            key    = "node.cilium.io/agent-not-ready"
            value  = "true"
            effect = "NoExecute"
          }]

          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot", "on-demand"]
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.k8s.aws/instance-category"
              operator = "In"
              values   = ["c", "m", "r"]
            },
            {
              key      = "karpenter.k8s.aws/instance-generation"
              operator = "Gt"
              values   = ["2"]
            },
          ]
        }
      }

      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
        budgets             = [{ nodes = "10%" }]
      }

      limits = {
        cpu = "1000"
      }
    }
  })

  depends_on = [kubectl_manifest.karpenter_node_class]
}
