include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../..//modules/platform"
}

dependency "cluster" {
  config_path = "../cluster"

  mock_outputs = {
    cluster_name           = "sanctum-mock"
    cluster_arn            = "arn:aws:eks:eu-central-1:000000000000:cluster/sanctum-mock"
    node_security_group_id = "sg-11111111111111111"
  }
}

# vpc_id comes from the network unit: this eks module does not expose it (the reference
# cluster module bundled the VPC, this one keeps them as separate units).
dependency "network" {
  config_path = "../network"

  mock_outputs = {
    vpc_id                    = "vpc-00000000000000000"
    private_subnet_ids        = ["subnet-private-a", "subnet-private-b", "subnet-private-c"]
    data_subnet_ids           = ["subnet-data-a", "subnet-data-b", "subnet-data-c"]
    default_security_group_id = "sg-00000000000000000"
  }
}

inputs = {
  cluster_name = dependency.cluster.outputs.cluster_name
  vpc_id       = dependency.network.outputs.vpc_id
  region       = include.root.locals.region
  environment  = include.root.locals.environment
}
