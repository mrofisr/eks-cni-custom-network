variable "profile" {
  description = "AWS profile to use for authentication"
  type        = string
  default     = "223880538604_LZ-PlatformAdministrator"
}

variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-southeast-3"
}

################################################################################
# EKS Cluster
################################################################################

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "eks-cni-workshop"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.32"
}

variable "eks_managed_node_groups" {
  description = "Bootstrap managed node group — runs CoreDNS, kube-proxy, Karpenter"
  type        = map(any)
  default = {
    main = {
      name                     = "bootstrap-nodes"
      instance_types           = ["t4g.xlarge"]
      capacity_type            = "SPOT"
      spot_allocation_strategy = "capacity-optimized"
      min_size                 = 1
      max_size                 = 3
      desired_size             = 2
      disk_size                = 100
      ami_type                 = "BOTTLEROCKET_ARM_64"
    }
  }
}

################################################################################
# Karpenter
################################################################################

variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.11.1"
}

################################################################################
# Tags
################################################################################

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    "Project"     = "EKS-CNI-Workshop"
    "Environment" = "Workshop"
    "Terraform"   = "true"
    "ManagedBy"   = "terraform"
  }
}
