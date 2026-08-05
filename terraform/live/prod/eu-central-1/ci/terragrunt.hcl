include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../..//modules/github-oidc"
}

dependency "cluster" {
  config_path = "../cluster"

  mock_outputs = {
    cluster_name           = "nimbus-mock"
    cluster_arn            = "arn:aws:eks:eu-central-1:000000000000:cluster/nimbus-mock"
    oidc_provider_arn      = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/MOCK"
    node_security_group_id = "sg-11111111111111111"
  }
}

inputs = {
  role_name      = "nimbus-github-actions-${include.root.locals.environment}"
  subject_claims = ["repo:nimbus-org/nimbus:ref:refs/heads/main"]

  ecr_repository_arns = [
    "arn:aws:ecr:${include.root.locals.region}:${include.root.locals.account_id}:repository/nimbus/podinfo",
  ]

  eks_cluster_arns = [dependency.cluster.outputs.cluster_arn]
  state_bucket_arn = "arn:aws:s3:::nimbus-tfstate-${include.root.locals.account_id}"
  lock_table_arn   = "arn:aws:dynamodb:${include.root.locals.region}:${include.root.locals.account_id}:table/nimbus-tflock"
}
