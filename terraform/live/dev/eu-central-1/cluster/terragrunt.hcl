include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../..//modules/eks"
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

locals {
  is_prod = include.root.locals.environment == "prod"
}

inputs = {
  cluster_name       = "nimbus-${include.root.locals.environment}"
  vpc_id             = dependency.network.outputs.vpc_id
  private_subnet_ids = dependency.network.outputs.private_subnet_ids

  endpoint_public_access = true
  # prod pins the public API endpoint to a single admin CIDR; dev allows a broader range.
  public_access_cidrs = local.is_prod ? ["203.0.113.10/32"] : ["203.0.113.0/24"]

  node_instance_types = local.is_prod ? ["m6i.xlarge"] : ["m6i.large"]
  node_min_size       = local.is_prod ? 3 : 1
  node_max_size       = local.is_prod ? 10 : 3
  node_desired_size   = local.is_prod ? 4 : 2
}
