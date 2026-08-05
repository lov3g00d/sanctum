locals {
  env          = "dev"
  cluster_name = "nimbus-dev"

  ecr_repository_arns = [
    "arn:aws:ecr:${var.region}:${var.account_id}:repository/nimbus/nimbus-orders-api",
    "arn:aws:ecr:${var.region}:${var.account_id}:repository/nimbus/nimbus-ledger",
  ]
}

module "vpc" {
  source = "../../modules/vpc"

  name               = "nimbus-${local.env}"
  cidr_block         = var.vpc_cidr
  azs                = var.azs
  single_nat_gateway = true
  eks_cluster_name   = local.cluster_name
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  endpoint_public_access = true
  public_access_cidrs    = var.eks_public_access_cidrs
  admin_access_entries   = var.eks_admin_arns

  node_instance_types = ["m6i.large"]
  node_min_size       = 1
  node_max_size       = 3
  node_desired_size   = 2
}

module "rds" {
  source = "../../modules/rds"

  identifier            = "nimbus-${local.env}"
  vpc_id                = module.vpc.vpc_id
  data_subnet_ids       = module.vpc.data_subnet_ids
  app_security_group_id = module.eks.node_security_group_id

  instance_class          = "db.t4g.medium"
  multi_az                = false
  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true
}

module "ledger" {
  source = "../../modules/serverless-api"

  name         = "nimbus-ledger-${local.env}"
  package_path = var.ledger_package_path

  reserved_concurrency = -1
  log_retention_days   = 14

  ssm_parameter_arns = var.ledger_ssm_parameter_arns
  environment_variables = {
    NIMBUS_ENV = local.env
  }
}

module "cloudflare" {
  source = "../../modules/cloudflare"
  count  = var.enable_cloudflare ? 1 : 0

  zone_id         = var.cloudflare_zone_id
  origin_hostname = var.cloudflare_origin_hostname

  rate_limit_requests_per_period = 600
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  role_name      = "nimbus-github-actions-${local.env}"
  subject_claims = var.github_subject_claims

  ecr_repository_arns = local.ecr_repository_arns
  eks_cluster_arns    = [module.eks.cluster_arn]
  state_bucket_arn    = "arn:aws:s3:::nimbus-tfstate-${var.account_id}"
  lock_table_arn      = "arn:aws:dynamodb:${var.region}:${var.account_id}:table/nimbus-tflock"
}
