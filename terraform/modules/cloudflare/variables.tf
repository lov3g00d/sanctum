variable "zone_id" {
  description = "Cloudflare zone ID for nimbus.example.com."
  type        = string
}

variable "record_name" {
  description = "Fully qualified record name proxied at the edge."
  type        = string
  default     = "api.nimbus.example.com"
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
