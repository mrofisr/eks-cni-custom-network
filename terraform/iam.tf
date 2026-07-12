################################################################################
# Karpenter Subnet Tags
################################################################################

# [ADDED] VPC CNI IAM Role (Pod Identity) for aws-node daemonset
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

# [ADDED] Tag subnets for Karpenter discovery - required for Karpenter to find subnets
resource "aws_ec2_tag" "karpenter_subnet_tags" {
  for_each    = toset(module.vpc.private_subnets)
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

# [ADDED] Tag cluster security group for Karpenter discovery
resource "aws_ec2_tag" "karpenter_security_group_tag" {
  resource_id = module.eks.cluster_primary_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

################################################################################
# Alloy CloudWatch IRSA Role
################################################################################

resource "aws_iam_role" "alloy_cloudwatch" {
  name = "${var.cluster_name}-alloy-cloudwatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:sub" = "system:serviceaccount:monitoring:alloy"
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "alloy_cloudwatch" {
  name = "${var.cluster_name}-alloy-cloudwatch"
  role = aws_iam_role.alloy_cloudwatch.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "iam:ListAccountAliases",
        "tag:GetResources",
        "ec2:DescribeInstances",
        "ec2:DescribeVolumes",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetHealth",
        "sqs:GetQueueAttributes",
        "sqs:ListQueues",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ]
      Resource = "*"
    }]
  })
}

