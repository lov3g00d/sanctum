output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "IRSA/OIDC provider ARN."
  value       = module.eks.oidc_provider_arn
}

output "rds_endpoint" {
  description = "RDS connection endpoint."
  value       = module.rds.db_instance_endpoint
}

output "rds_master_secret_arn" {
  description = "Secrets Manager ARN for the RDS master credentials."
  value       = module.rds.master_user_secret_arn
}

output "ledger_api_endpoint" {
  description = "nimbus-ledger HTTP API endpoint."
  value       = module.ledger.api_endpoint
}

output "cloudflare_record" {
  description = "Proxied hostname served at the Cloudflare edge (null when enable_cloudflare is false)."
  value       = one(module.cloudflare[*].record_hostname)
}

output "ci_role_arn" {
  description = "GitHub Actions CI role ARN."
  value       = module.github_oidc.role_arn
}
