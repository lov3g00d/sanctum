include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../..//modules/rds"
}

dependency "network" {
  config_path = "../network"

  mock_outputs = {
    vpc_id                    = "vpc-00000000000000000"
    private_subnet_ids        = ["subnet-private-a", "subnet-private-b", "subnet-private-c"]
    data_subnet_ids           = ["subnet-data-a", "subnet-data-b", "subnet-data-c"]
    default_security_group_id = "sg-00000000000000000"
  }
}

dependency "cluster" {
  config_path = "../cluster"

  mock_outputs = {
    cluster_name           = "sanctum-mock"
    cluster_arn            = "arn:aws:eks:eu-central-1:000000000000:cluster/sanctum-mock"
    oidc_provider_arn      = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/MOCK"
    node_security_group_id = "sg-11111111111111111"
  }
}

locals {
  is_prod = include.root.locals.environment == "prod"
}

inputs = {
  identifier            = "sanctum-${include.root.locals.environment}"
  vpc_id                = dependency.network.outputs.vpc_id
  data_subnet_ids       = dependency.network.outputs.data_subnet_ids
  app_security_group_id = dependency.cluster.outputs.node_security_group_id

  instance_class          = local.is_prod ? "db.r6g.large" : "db.t4g.medium"
  multi_az                = include.root.locals.ha
  deletion_protection     = include.root.locals.ha
  skip_final_snapshot     = !include.root.locals.ha
  backup_retention_period = local.is_prod ? 30 : 7
}
