terraform {
  backend "s3" {
    bucket         = "nimbus-tfstate-210987654321"
    key            = "nimbus/prod/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "nimbus-tflock"
  }
}
