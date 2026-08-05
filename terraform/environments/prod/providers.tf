provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "nimbus"
      Environment = "prod"
      ManagedBy   = "terraform"
      Owner       = "platform-team"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
