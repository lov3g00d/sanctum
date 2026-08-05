variable "name" {
  description = "Name prefix for the VPC and all child resources (e.g. sanctum-dev)."
  type        = string
}

variable "cidr_block" {
  description = "Primary IPv4 CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across. Three for AZ-level resilience."
  type        = list(string)

  validation {
    condition     = length(var.azs) == 3
    error_message = "Provide exactly three availability zones."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs for the public subnet tier (one per AZ). Holds load balancers and NAT gateways."
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs for the private subnet tier (one per AZ). Holds EKS nodes and Lambda ENIs."
  type        = list(string)
  default     = ["10.0.48.0/20", "10.0.64.0/20", "10.0.80.0/20"]
}

variable "data_subnet_cidrs" {
  description = "CIDRs for the data subnet tier (one per AZ). Holds RDS, ElastiCache; no route to the internet."
  type        = list(string)
  default     = ["10.0.96.0/22", "10.0.100.0/22", "10.0.104.0/22"]
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cost-optimized, dev) instead of one per AZ (HA, prod)."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "Retention for the VPC Flow Logs CloudWatch log group."
  type        = number
  default     = 30
}

variable "eks_cluster_name" {
  description = "EKS cluster name used to tag subnets for load-balancer autodiscovery. Empty disables the tags."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to every resource in addition to provider default_tags."
  type        = map(string)
  default     = {}
}
