variable "profile" {
  description = "AWS Profile to Execute this Terraform"
  type        = string
  default     = "223880538604_LZ-PlatformAdministrator"
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
    "ava/genai-api",
    "ava/genai-web",
    "ava/genai-plugin-daemon",
    "ava/genai-weaviate",
    "ava/genai-valkey",
    "ava/genai-postgres",
    "ava/genai-firecrawl",
    "ava/genai-playwright",
    "ava/genai-nginx",
    "ava/genai-sandbox",
    "ava/genai-mcp",
    "ava/grafana-alloy",
    "ava/grafana-grafana",
    "ava/grafana-mimir",
    "ava/grafana-alertmanager",
    "ava/prometheus-msteams",
    "ava/grafana-loki",
    "ava/busybox",
    "ava/nginx-prometheus-exporter"
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
  default     = "1.35"
}

variable "eks_managed_node_groups" {
  description = "Map of EKS managed node group definitions to create"
  type        = map(any)
  default = {
    main = {
      name                     = "ava-eks-nodes"
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
    "Project"     = "AVA"
    "Environment" = "Prod"
    "Terraform"   = "true"
    "OwnerTeam"   = "AVA"
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
  default     = "1.11.1"
}
