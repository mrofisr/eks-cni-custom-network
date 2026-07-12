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
# ECR
################################################################################

output "ecr_repository_urls" {
  description = "ECR repository name → URL map"
  value       = { for k, v in module.ecr : k => v.repository_url }
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
# S3
################################################################################

output "s3_tfstate_bucket_id" {
  description = "S3 state bucket name"
  value       = module.s3_tfstate.s3_bucket_id
}

output "s3_tfstate_bucket_arn" {
  description = "S3 state bucket ARN"
  value       = module.s3_tfstate.s3_bucket_arn
}

output "s3_data_bucket_id" {
  description = "S3 data bucket name"
  value       = module.s3_data.s3_bucket_id
}

output "s3_data_bucket_arn" {
  description = "S3 data bucket ARN"
  value       = module.s3_data.s3_bucket_arn
}

################################################################################
# Gateway EIPs
################################################################################

output "gateway_eip_allocations" {
  description = "Elastic IP allocation IDs for public NLB"
  value       = [for eip in aws_eip.gateway : eip.id]
}

################################################################################
# Alloy
################################################################################

output "alloy_cloudwatch_role_arn" {
  description = "Alloy IRSA role ARN for CloudWatch metrics"
  value       = aws_iam_role.alloy_cloudwatch.arn
}

################################################################################
# VPC
################################################################################

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "intra_subnets" {
  description = "Intra subnet IDs (CNI custom networking)"
  value       = module.vpc.intra_subnets
}

