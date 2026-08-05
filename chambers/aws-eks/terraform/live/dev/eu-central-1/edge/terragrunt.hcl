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

inputs = {
  zone_id     = "0123456789abcdef0123456789abcdef"
  record_name = "podinfo.example.com"

  # Managed WAF and advanced rate limiting are Pro+ features; leave false on a Free
  # zone, set true on a paid plan.
  enable_waf = false

  # ALB origin, populated once the ingress exists.
  origin_hostname = "${include.root.locals.environment}-podinfo.eu-central-1.elb.amazonaws.com"
}
