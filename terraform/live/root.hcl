terraform_version_constraint  = ">= 1.6"
terragrunt_version_constraint = ">= 1.0.0"

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  account_id  = local.env_vars.locals.account_id
  environment = local.env_vars.locals.environment
  ha          = local.env_vars.locals.ha

  # Path is <env>/<region>/<unit>, so element 1 is the region.
  region = split("/", path_relative_to_include())[1]
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }

  config = {
    bucket       = "nimbus-tfstate-${local.account_id}"
    key          = "live/${path_relative_to_include()}/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.region}"

      default_tags {
        tags = {
          Project     = "nimbus"
          Environment = "${local.environment}"
          ManagedBy   = "terraform"
          Owner       = "platform-team"
        }
      }
    }
  EOF
}
