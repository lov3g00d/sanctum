include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../..//modules/vpc"
}

inputs = {
  name             = "sanctum-${include.root.locals.environment}"
  azs              = ["${include.root.locals.region}a", "${include.root.locals.region}b", "${include.root.locals.region}c"]
  eks_cluster_name = "sanctum-${include.root.locals.environment}"

  # prod runs one NAT gateway per AZ for AZ-fault tolerance; dev shares one to cut cost.
  single_nat_gateway = !include.root.locals.ha
}
