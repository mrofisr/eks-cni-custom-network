variable "profile" {
  description = "AWS Profile to Execute this Terraform"
  type        = string
  default     = "default"
}

variable "region" {
  description = "AWS Region to Execute this Terraform"
  type        = string
  default     = "ap-southeast-3"
}

################################################################################
# ECR
################################################################################

variable "repository_name" {
  description = "List of ECR repository names to create"
  type        = list(string)
  default = [
    "jawaracloud/retail-store-sample-catalog",
    "jawaracloud/retail-store-sample-ui",
    "jawaracloud/mysql",
    "jawaracloud/grafana-alloy",
    "jawaracloud/grafana-grafana",
    "jawaracloud/busybox"
  ]
}

################################################################################
# EKS CLUSTER
################################################################################

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "eks-default"
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.36"
}

variable "eks_managed_node_groups" {
  description = "Map of EKS managed node group definitions to create"
  type        = map(any)
  default = {
    main = {
      name                     = "jawaracloud-eks-nodes"
      instance_types           = ["t4g.xlarge"]
      capacity_type            = "SPOT"
      spot_allocation_strategy = "capacity-optimized"
      min_size                 = 1
      max_size                 = 1
      desired_size             = 1
      disk_size                = 100
      ami_type                 = "BOTTLEROCKET_ARM_64"
    }
  }
}

variable "vpc_id" {
  description = "ID of the VPC where the cluster and its nodes will be provisioned"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs where the EKS cluster will be provisioned"
  type        = list(string)
  default     = ["", ""]
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default = {
    "Project"     = "JawaraCloud"
    "Environment" = "Prod"
    "Terraform"   = "true"
    "OwnerTeam"   = "JawaraCloud"
  }
}

################################################################################
# EC2 BASTION
################################################################################

variable "instance_subnet_id" {
  description = "ID of the subnet where the EC2 instance will be launched"
  type        = string
  default     = ""
}

################################################################################
# KARPENTER
################################################################################

# [ADDED] Karpenter version variable
variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.14.0"
}

#################################################################################
# VPC
#################################################################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks for the VPC (used for CNI custom networking)"
  type        = list(string)
  default     = ["100.64.0.0/16"]
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "intra_subnets" {
  description = "Intra subnet CIDR blocks for CNI custom networking"
  type        = list(string)
  default     = ["100.64.1.0/24", "100.64.2.0/24", "100.64.3.0/24"]
}
