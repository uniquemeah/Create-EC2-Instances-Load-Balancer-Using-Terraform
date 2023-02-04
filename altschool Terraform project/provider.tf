terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
    }
  }
}

terraform {
  backend "local" {
    path = "inventory"
}
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}
