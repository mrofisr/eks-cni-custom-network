terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.40.0"
    }
  }

  backend "s3" {
    bucket         = ""
    key            = "terraform.tfstate"
    profile        = ""
    region         = "ap-southeast-3"
    # dynamodb_table = "terraform-lock" # Uncomment after creating the DynamoDB table
    encrypt = true
  }
}

provider "aws" {
  profile = "223880538604_LZ-PlatformAdministrator"
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
