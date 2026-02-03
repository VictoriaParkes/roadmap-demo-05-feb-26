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
}

# provider "tls" {
#   # Configuration options
# }