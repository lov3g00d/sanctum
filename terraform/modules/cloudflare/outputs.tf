output "record_hostname" {
  description = "Proxied hostname served at the Cloudflare edge."
  value       = cloudflare_dns_record.api.name
}

output "managed_waf_ruleset_id" {
  description = "ID of the managed WAF ruleset deployment."
  value       = cloudflare_ruleset.managed_waf.id
}

output "rate_limit_ruleset_id" {
  description = "ID of the rate-limit ruleset."
  value       = cloudflare_ruleset.rate_limit.id
}
