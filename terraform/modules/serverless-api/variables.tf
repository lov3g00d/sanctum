variable "name" {
  description = "Function and API name (e.g. nimbus-ledger-dev)."
  type        = string
}

variable "package_path" {
  description = "Path to the deployment .zip. source_code_hash is derived from it so a rebuilt package redeploys."
  type        = string
}

variable "handler" {
  description = "Lambda handler entrypoint."
  type        = string
  default     = "app.main.handler"
}

variable "runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "python3.13"
}

variable "memory_size" {
  description = "Memory in MB (also scales CPU)."
  type        = number
  default     = 512
}

variable "timeout" {
  description = "Function timeout in seconds."
  type        = number
  default     = 30
}

variable "reserved_concurrency" {
  description = "Reserved concurrent executions. -1 leaves the function on the unreserved pool."
  type        = number
  default     = -1
}

variable "log_retention_days" {
  description = "Retention for the function log group. Explicit so logs are not kept forever by default."
  type        = number
  default     = 30
}

variable "environment_variables" {
  description = "Plain, non-secret environment variables."
  type        = map(string)
  default     = {}
}

variable "ssm_parameter_arns" {
  description = "SSM parameter ARNs the function reads at runtime. The role is granted GetParameter on exactly these; values are resolved in-function so no secret enters Terraform state."
  type        = list(string)
  default     = []
}

variable "ssm_kms_key_arn" {
  description = "KMS key ARN used to decrypt SecureString SSM parameters. Empty grants no extra kms:Decrypt."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to the function resources."
  type        = map(string)
  default     = {}
}
