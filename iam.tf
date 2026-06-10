################################################################################
# VPC CNI — Pod Identity
################################################################################

resource "aws_iam_role" "vpc_cni" {
  name = "${var.cluster_name}-vpc-cni"

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

# Associate the VPC CNI role with the aws-node daemonset via Pod Identity
resource "aws_eks_pod_identity_association" "vpc_cni" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-node"
  role_arn        = aws_iam_role.vpc_cni.arn

  tags = var.tags
}

################################################################################
# Karpenter — subnet + security group discovery tags
################################################################################

# Tag private subnets for Karpenter node provisioning
resource "aws_ec2_tag" "karpenter_subnet_tags" {
  for_each    = toset(module.vpc.private_subnets)
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

# Tag cluster security group for Karpenter discovery
resource "aws_ec2_tag" "karpenter_security_group_tag" {
  resource_id = module.eks.cluster_primary_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}
