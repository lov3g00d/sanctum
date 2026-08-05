terraform {
  backend "s3" {
    bucket         = "nimbus-tfstate-123456789012"
    key            = "nimbus/dev/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "nimbus-tflock"
  }
}
