# Scoped read access for the External Secrets Operator. Rather than the module's broad
# built-in policy, this grants only the reads ESO performs, and only under the nimbus/
# name prefix, so a compromised operator cannot pull unrelated account secrets.
data "aws_iam_policy_document" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  statement {
    sid = "SecretsManagerRead"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = ["arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:nimbus/*"]
  }

  statement {
    sid = "SSMParameterRead"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/nimbus/*"]
  }
}

resource "aws_iam_policy" "external_secrets" {
  count       = var.enable_external_secrets ? 1 : 0
  name        = "external-secrets-${var.cluster_name}"
  description = "Scoped SecretsManager/SSM read access for External Secrets under nimbus/*"
  policy      = data.aws_iam_policy_document.external_secrets[0].json
  tags        = local.common_tags
}

module "external_secrets_pod_identity" {
  count   = var.enable_external_secrets ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.8.2"

  name            = "external-secrets-${var.cluster_name}"
  use_name_prefix = false

  additional_policy_arns = {
    external_secrets = aws_iam_policy.external_secrets[0].arn
  }

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }

  tags = local.common_tags
}

resource "helm_release" "external_secrets" {
  count      = var.enable_external_secrets ? 1 : 0
  name       = "external-secrets"
  namespace  = kubernetes_namespace.external_secrets[0].metadata[0].name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.external_secrets_chart_version

  atomic = true
  wait   = true

  values = [
    yamlencode({
      installCRDs = true

      serviceAccount = {
        create = true
        name   = "external-secrets"
      }

      replicaCount = 2
    })
  ]
}

# Cluster-wide entry point for SecretManager-backed ExternalSecrets. With Pod Identity the
# store carries no auth block: ESO uses the controller pod's ambient credentials from the
# association above (the jwt/serviceAccountRef path is IRSA-only and cannot impersonate a
# Pod Identity role). Individual namespaces reference this store by name without handling
# AWS credentials.
resource "kubectl_manifest" "cluster_secret_store" {
  count = var.enable_external_secrets ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secretsmanager"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
        }
      }
    }
  })

  depends_on = [helm_release.external_secrets]
}
