output "role_arn" {
  description = "ARN of the CI role. Set this as the aws-actions/configure-aws-credentials role-to-assume."
  value       = aws_iam_role.ci.arn
}

output "role_name" {
  description = "Name of the CI role."
  value       = aws_iam_role.ci.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider in use."
  value       = local.oidc_provider_arn
}
