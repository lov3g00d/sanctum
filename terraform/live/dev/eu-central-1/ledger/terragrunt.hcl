include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../..//modules/serverless-api"
}

locals {
  is_prod = include.root.locals.environment == "prod"
}

inputs = {
  name         = "nimbus-ledger-${include.root.locals.environment}"
  package_path = "${get_repo_root()}/app/ledger-py/dist/nimbus-ledger.zip"

  reserved_concurrency = local.is_prod ? 50 : -1
  log_retention_days   = local.is_prod ? 30 : 14

  environment_variables = {
    NIMBUS_ENV = include.root.locals.environment
  }
}
