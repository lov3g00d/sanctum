variable "zone_id" {
  description = "Cloudflare zone ID for sanctum.example.com."
  type        = string
}

variable "record_name" {
  description = "Fully qualified record name proxied at the edge."
  type        = string
  default     = "api.sanctum.example.com"
}

variable "enable_waf" {
  description = "Deploy the managed WAF and rate-limit rulesets. Requires a paid (Pro+) plan; set false on a Free zone."
  type        = bool
  default     = true
}

variable "origin_hostname" {
  description = "AWS origin the proxied record points at (ALB or API Gateway DNS name)."
  type        = string
}

variable "rate_limit_requests_per_period" {
  description = "Requests allowed per rate-limit period, per client IP."
  type        = number
  default     = 300
}

variable "rate_limit_period" {
  description = "Rate-limit window in seconds (10, 60, 120, ...)."
  type        = number
  default     = 60
}

variable "rate_limit_mitigation_timeout" {
  description = "Seconds a client stays blocked after tripping the rate limit."
  type        = number
  default     = 60
}

variable "origin_cert_id" {
  description = "Authenticated Origin Pulls certificate ID. Empty uses the Cloudflare-managed certificate zone-wide."
  type        = string
  default     = ""
}
