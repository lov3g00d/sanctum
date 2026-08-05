variable "role_name" {
  description = "Name of the IAM role GitHub Actions assumes."
  type        = string
  default     = "sanctum-github-actions"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if one already exists in the account (one per account is enough)."
  type        = bool
  default     = true
}

variable "subject_claims" {
  description = "Allowed token subjects. Scope to a repo and ref, e.g. repo:sanctum-org/sanctum:ref:refs/heads/main."
  type        = list(string)

  validation {
    condition     = length(var.subject_claims) > 0
    error_message = "Provide at least one subject claim so the role is not assumable by any repo."
  }
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs CI may push to."
  type        = list(string)
  default     = []
}

variable "eks_cluster_arns" {
  description = "EKS cluster ARNs CI may describe to fetch kubeconfig."
  type        = list(string)
  default     = []
}

variable "state_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket."
  type        = string
}

variable "tags" {
  description = "Tags applied to the IAM resources."
  type        = map(string)
  default     = {}
}
