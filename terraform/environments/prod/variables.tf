variable "account_id" {
  description = "AWS account ID this environment deploys into."
  type        = string
}

variable "region" {
  description = "Primary AWS region."
  type        = string
  default     = "eu-central-1"
}

variable "azs" {
  description = "Availability zones for the three subnet tiers."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.20.0.0/16"
}

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.33"
}

variable "eks_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint. Keep this tight in prod."
  type        = list(string)
}

variable "eks_admin_arns" {
  description = "IAM principal ARNs granted cluster-admin via access entries."
  type        = list(string)
  default     = []
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token. Pass via TF_VAR_cloudflare_api_token, never commit it."
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for nimbus.example.com."
  type        = string
}

variable "cloudflare_origin_hostname" {
  description = "AWS origin hostname Cloudflare proxies to (the orders-api ALB DNS name)."
  type        = string
}

variable "github_subject_claims" {
  description = "GitHub OIDC subject claims allowed to assume the CI role."
  type        = list(string)
}

variable "ledger_package_path" {
  description = "Path to the built nimbus-ledger Lambda .zip."
  type        = string
  default     = "../../../app/ledger-py/dist/nimbus-ledger.zip"
}

variable "ledger_ssm_parameter_arns" {
  description = "SSM parameter ARNs the ledger function reads at runtime."
  type        = list(string)
  default     = []
}
