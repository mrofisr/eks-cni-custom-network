
################################################################################
# EC2 IAM Role for Bastion Host
################################################################################

resource "aws_iam_role" "ec2_bastion_role" {
  name = "${var.cluster_name}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# SSM access — connect to bastion without SSH keys or open security groups
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ec2_bastion_role.name
}

# EKS read + kubectl access
resource "aws_iam_role_policy" "bastion_eks_access" {
  name = "${var.cluster_name}-bastion-eks-access"
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
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "${var.cluster_name}-bastion-profile"
  role = aws_iam_role.ec2_bastion_role.name
}

################################################################################
# EC2 Bastion Instance
# Access via SSM Session Manager — no public IP, no SSH key needed:
#   aws ssm start-session --target <instance-id> --region ap-southeast-3
################################################################################

module "ec2" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "6.4.0"

  name          = "${var.cluster_name}-bastion"
  instance_type = "t4g.medium"
  ami           = "ami-0230da38227b63e1a" # Ubuntu 22.04 ARM64 ap-southeast-3

  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [module.eks.cluster_primary_security_group_id]

  iam_instance_profile = aws_iam_instance_profile.bastion_profile.name

  user_data_base64 = base64encode(file("${path.module}/init.sh"))

  # No public IP — access only via SSM
  create_security_group = false

  # IMDSv2 required
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Termination protection — prevent accidental destroy
  disable_api_termination = true

  monitoring = false

  root_block_device = {
    volume_type           = "gp3"
    volume_size           = 30
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true
  }

  tags       = var.tags
  depends_on = [module.eks]
}
