include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../..//modules/cloudflare"
}

# The edge unit needs the Cloudflare provider on top of the AWS provider from root.hcl.
# The token is read from CLOUDFLARE_API_TOKEN, never committed.
generate "cloudflare_provider" {
  path      = "provider_cloudflare.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "cloudflare" {}
  EOF
}

locals {
  is_prod = include.root.locals.environment == "prod"
}

inputs = {
  zone_id         = "0123456789abcdef0123456789abcdef"
  origin_hostname = "${include.root.locals.environment}-podinfo.eu-central-1.elb.amazonaws.com"

  rate_limit_requests_per_period = local.is_prod ? 300 : 600
}
