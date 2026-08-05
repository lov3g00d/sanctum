resource "cloudflare_dns_record" "api" {
  zone_id = var.zone_id
  name    = var.record_name
  type    = "CNAME"
  content = var.origin_hostname
  proxied = true
  ttl     = 1
}

resource "cloudflare_zone_setting" "ssl" {
  zone_id    = var.zone_id
  setting_id = "ssl"
  value      = "strict"
}

resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = var.zone_id
  setting_id = "always_use_https"
  value      = "on"
}

# Cloudflare validates a client certificate on every origin request, so the origin
# can reject anything that did not come through Cloudflare. Empty origin_cert_id
# uses the Cloudflare-managed certificate for the whole zone.
resource "cloudflare_authenticated_origin_pulls" "this" {
  zone_id = var.zone_id
  config = [{
    enabled = true
    cert_id = var.origin_cert_id == "" ? null : var.origin_cert_id
  }]
}

# execute the Cloudflare Managed Ruleset (managed WAF). The id is the well-known,
# account-independent identifier of that ruleset.
resource "cloudflare_ruleset" "managed_waf" {
  # Managed WAF rulesets are a paid (Pro+) entitlement; disable on a Free zone.
  count = var.enable_waf ? 1 : 0

  zone_id = var.zone_id
  name    = "sanctum-managed-waf"
  kind    = "zone"
  phase   = "http_request_firewall_managed"

  rules = [{
    action      = "execute"
    expression  = "true"
    description = "Cloudflare Managed Ruleset"
    enabled     = true
    action_parameters = {
      id = "efb7b8c949ac4650a09736fc376e9aee"
    }
  }]
}

resource "cloudflare_ruleset" "rate_limit" {
  # Rate-limiting rules with these characteristics are a paid entitlement; the Free
  # plan allows only a single basic rule. Gated with the managed WAF for simplicity.
  count = var.enable_waf ? 1 : 0

  zone_id = var.zone_id
  name    = "sanctum-rate-limit"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [{
    action      = "block"
    expression  = "(http.host eq \"${var.record_name}\")"
    description = "Per-IP rate limit on the API"
    enabled     = true
    ratelimit = {
      characteristics     = ["ip.src", "cf.colo.id"]
      period              = var.rate_limit_period
      requests_per_period = var.rate_limit_requests_per_period
      mitigation_timeout  = var.rate_limit_mitigation_timeout
    }
  }]
}
