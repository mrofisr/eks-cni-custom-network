
################################################################################
# EC2 IAM Role for Bastion Host
################################################################################

resource "aws_iam_role" "ec2_bastion_role" {
  name = "${local.resource_name}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "ec2.amazonaws.com",
            "eks.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "bastion_ecr_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
  role       = aws_iam_role.ec2_bastion_role.name
}

resource "aws_iam_role_policy_attachment" "bastion_eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.ec2_bastion_role.name
}

resource "aws_iam_role_policy_attachment" "bastion_ssm_managed_instance_core" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ec2_bastion_role.name
}

resource "aws_iam_role_policy_attachment" "bastion_eks_service_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.ec2_bastion_role.name
}

# Disabled - CloudWatch agent not needed to reduce costs
# resource "aws_iam_role_policy_attachment" "bastion_cloudwatch_agent" {
#   policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
#   role       = aws_iam_role.ec2_bastion_role.name
# }

resource "aws_iam_role_policy" "bastion_eks_access" {
  name = "${local.resource_name}-bastion-eks-access"
  role = aws_iam_role.ec2_bastion_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:DescribeAddon",
          "eks:ListAddons",
          "eks:AccessKubernetesApi"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = module.eks.cluster_iam_role_arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "${local.resource_name}-bastion-profile"
  role = aws_iam_role.ec2_bastion_role.name
}

################################################################################
# EC2 Bastion Instance
################################################################################

module "ec2" {
  source                 = "terraform-aws-modules/ec2-instance/aws"
  version                = "6.4.0"
  name                   = "${local.resource_name}-bastion"
  instance_type          = "t4g.xlarge"
  user_data_base64       = base64encode(file("${path.module}/init.sh"))
  vpc_security_group_ids = [module.eks.cluster_primary_security_group_id]
  subnet_id              = module.vpc.private_subnets[0]
  ami                    = "ami-0230da38227b63e1a"
  iam_instance_profile   = aws_iam_instance_profile.bastion_profile.name

  # Disable module-created SG - using EKS cluster SG instead
  create_security_group = true
  security_group_vpc_id = module.vpc.vpc_id

  # [ADDED] Enable detailed monitoring for CloudWatch metrics at 1-minute intervals
  monitoring = false

  # [ADDED] Enable termination protection to prevent accidental deletion
  disable_api_termination = true

  # [ADDED] Metadata options - IMDSv2 required for security best practice
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device = {
    volume_type           = "gp3"
    volume_size           = 50
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true
  }

  tags       = var.tags
  depends_on = [module.eks]
}
