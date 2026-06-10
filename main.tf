terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.40.0"
    }
  }

  # Fill in your S3 bucket and AWS profile before running terraform init
  backend "s3" {
    bucket  = ""                  # e.g. "my-tfstate-bucket"
    key     = "eks-cni-workshop/terraform.tfstate"
    profile = ""                  # e.g. "my-aws-profile"
    region  = "ap-southeast-3"
    encrypt = true
    # dynamodb_table = "terraform-lock"  # Uncomment to enable state locking
  }
}

provider "aws" {
  profile = var.profile
  region  = var.region

  default_tags {
    tags = var.tags
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
