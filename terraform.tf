terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.30.0"
    }

    # tls = {
    #   source  = "hashicorp/tls"
    #   version = "4.2.1"
    # }
  }
}

provider "aws" {
  region = var.region
  assume_role {
    role_arn     = "arn:aws:iam::${var.account_id}:role/terraform-execution"
    session_name = "terraform-session-example"
  }
}

# provider "tls" {
#   # Configuration options
# }