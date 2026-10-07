terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.42.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.27.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.0"
    }
  }

  # backend "s3" {
  #   bucket  = "eks-default-tfstate"
  #   key     = "terraform.tfstate"
  #   region  = "ap-southeast-3"
  #   encrypt = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
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

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  # Use last 6 digits of account ID + short region to keep within IAM 38-char name_prefix limit
  # EKS module appends "-cluster-" (9 chars), so resource_name must be <= 29 chars
  # e.g. "617931-apse3-eks-default" = 24 chars + "-cluster-" = 33 chars ✓
  account_short = substr(local.account_id, 6, 6)
  region_short  = replace(replace(replace(local.region, "ap-southeast-", "apse"), "ap-northeast-", "apne"), "ap-south-", "aps")
  name_prefix   = "${local.account_short}-${local.region_short}"
  resource_name = "${local.name_prefix}-${var.cluster_name}"
}
