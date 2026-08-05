variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes control plane version (<major>.<minor>)."
  type        = string
  default     = "1.33"
}

variable "vpc_id" {
  description = "VPC the cluster is deployed into."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the control plane ENIs and managed node group."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Whether the public API endpoint is enabled. Off by default (private); an environment opts in and must restrict it with public_access_cidrs."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Never leave this at 0.0.0.0/0 for a real cluster."
  type        = list(string)
  default     = []
}

variable "enabled_log_types" {
  description = "Control plane log types shipped to CloudWatch."
  type        = list(string)
  default     = ["audit", "authenticator", "api"]
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["m6i.large"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT for the managed node group."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_min_size" {
  description = "Minimum node count."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum node count."
  type        = number
  default     = 5
}

variable "node_desired_size" {
  description = "Desired node count for the managed node group."
  type        = number
  default     = 3
}

variable "admin_access_entries" {
  description = "IAM principal ARNs granted cluster-admin via EKS access entries."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to cluster resources."
  type        = map(string)
  default     = {}
}
