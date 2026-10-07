################################################################################
# VPC CNI IAM Role (Pod Identity) for aws-node daemonset
################################################################################

resource "aws_iam_role" "vpc_cni" {
  name = "${local.resource_name}-vpc-cni"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni.name
}

# Bind the vpc-cni role to the aws-node ServiceAccount via EKS Pod Identity
resource "aws_eks_pod_identity_association" "vpc_cni" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-node"
  role_arn        = aws_iam_role.vpc_cni.arn
}

################################################################################
# Karpenter Subnet & Security Group Tags
################################################################################

resource "aws_ec2_tag" "karpenter_subnet_tags" {
  for_each    = { for idx, subnet in var.private_subnets : subnet => module.vpc.private_subnets[idx] }
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = local.resource_name

  depends_on = [module.vpc]
}

resource "aws_ec2_tag" "karpenter_security_group_tag" {
  resource_id = module.eks.cluster_primary_security_group_id
  key         = "karpenter.sh/discovery"
  value       = local.resource_name
}

