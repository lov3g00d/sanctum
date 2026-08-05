variable "identifier" {
  description = "DB instance identifier (e.g. nimbus-dev)."
  type        = string
}

variable "vpc_id" {
  description = "VPC the database lives in."
  type        = string
}

variable "data_subnet_ids" {
  description = "Data-tier subnet IDs for the DB subnet group. These have no route to the internet."
  type        = list(string)
}

variable "app_security_group_id" {
  description = "Security group of the application tier (EKS nodes). The only source allowed to reach the DB port."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL major.minor version."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.medium"
}

variable "allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 50
}

variable "max_allocated_storage" {
  description = "Upper bound for storage autoscaling in GiB. Set equal to allocated_storage to disable."
  type        = number
  default     = 200
}

variable "db_name" {
  description = "Name of the initial database."
  type        = string
  default     = "nimbus"
}

variable "master_username" {
  description = "Master username. The password is generated and stored in Secrets Manager, never in state."
  type        = string
  default     = "nimbus_admin"
}

variable "db_port" {
  description = "Port the database listens on."
  type        = number
  default     = 5432
}

variable "multi_az" {
  description = "Multi-AZ synchronous standby for automatic failover. On for prod, off for dev."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days of automated backups retained. Enables point-in-time recovery."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Block accidental deletion of the instance."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. True is acceptable for dev only."
  type        = bool
  default     = false
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention in days (7 for the free tier, or 31/93/... for long term)."
  type        = number
  default     = 7
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring granularity in seconds (0 disables; 1/5/10/15/30/60)."
  type        = number
  default     = 60
}

variable "tags" {
  description = "Tags applied to the database resources."
  type        = map(string)
  default     = {}
}
