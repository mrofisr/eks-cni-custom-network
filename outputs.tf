################################################################################
# EKS
################################################################################

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_ca" {
  description = "EKS cluster CA certificate (base64)"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "eks_oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "eks_kms_key_arn" {
  description = "KMS key ARN for EKS secrets encryption"
  value       = module.eks.kms_key_arn
}

output "eks_cluster_primary_security_group_id" {
  description = "EKS cluster primary security group ID — used in ENIConfig"
  value       = module.eks.cluster_primary_security_group_id
}

################################################################################
# VPC
################################################################################

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_public_subnets" {
  description = "Public subnet IDs (NAT GW, ALB)"
  value       = module.vpc.public_subnets
}

output "vpc_private_subnets" {
  description = "Private subnet IDs (EKS nodes)"
  value       = module.vpc.private_subnets
}

output "vpc_pod_subnets" {
  description = "Pod subnet IDs (secondary CIDR 100.64.0.0/16) — used in ENIConfig"
  value       = module.vpc.intra_subnets
}

output "vpc_azs" {
  description = "Availability zones used"
  value       = module.vpc.azs
}

################################################################################
# Karpenter
################################################################################

output "karpenter_controller_role_arn" {
  description = "Karpenter controller IAM role ARN (Pod Identity)"
  value       = module.karpenter.iam_role_arn
}

output "karpenter_node_role_name" {
  description = "Karpenter node IAM role name"
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_queue" {
  description = "Karpenter SQS interruption queue name"
  value       = module.karpenter.queue_name
}

################################################################################
# EC2 Bastion
################################################################################

output "bastion_instance_id" {
  description = "Bastion EC2 instance ID"
  value       = module.ec2.id
}

output "bastion_role_arn" {
  description = "Bastion IAM role ARN"
  value       = aws_iam_role.ec2_bastion_role.arn
}

################################################################################
# Workshop helpers
# Use these values to fill in manifests/eniconfig.yaml after terraform apply
################################################################################

output "workshop_eniconfig_hint" {
  description = "Values needed to fill manifests/eniconfig.yaml"
  value = {
    az_0             = module.vpc.azs[0]
    az_1             = module.vpc.azs[1]
    pod_subnet_az_0  = module.vpc.intra_subnets[0]
    pod_subnet_az_1  = module.vpc.intra_subnets[1]
    security_group   = module.eks.cluster_primary_security_group_id
  }
}
