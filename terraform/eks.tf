
################################################################################
# EKS Module (v21.x - uses built-in KMS key)
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.17.1"

  name               = local.resource_name
  kubernetes_version = var.cluster_version
  tags               = var.tags

  upgrade_policy = {
    support_type = "STANDARD"
  }

  cluster_tags = merge(var.tags, {
    "karpenter.sh/discovery" = local.resource_name
  })

  create_iam_role            = true
  create_node_iam_role       = true
  create_security_group      = true
  create_node_security_group = true

  endpoint_private_access = true
  endpoint_public_access  = false

  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.private_subnets

  # Built-in KMS key (create_kms_key = true by default in v21)
  # No need for separate module.kms

  enabled_log_types           = []
  create_cloudwatch_log_group = false

  addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
    aws-efs-csi-driver = {
      most_recent = true
    }
    amazon-cloudwatch-observability = {
      most_recent = true
    }
    aws-mountpoint-s3-csi-driver = {
      most_recent = true
    }
    eks-node-monitoring-agent = {
      most_recent = true
    }
    aws-secrets-store-csi-driver-provider = {
      most_recent = true
    }
    kube-state-metrics = {
      most_recent = true
    }
    metrics-server = {
      most_recent = true
    }
    cert-manager = {
      most_recent = true
    }
  }

  eks_managed_node_groups = {
    main = {
      name           = var.eks_managed_node_groups.main.name
      instance_types = var.eks_managed_node_groups.main.instance_types
      capacity_type  = var.eks_managed_node_groups.main.capacity_type
      min_size       = var.eks_managed_node_groups.main.min_size
      max_size       = var.eks_managed_node_groups.main.max_size
      desired_size   = var.eks_managed_node_groups.main.desired_size
      ami_type       = var.eks_managed_node_groups.main.ami_type

      enable_monitoring = false

      # [ADDED] Required IAM policies for node group
      iam_role_additional_policies = {
        AmazonEKS_CNI_Policy               = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        AmazonSSMManagedInstanceCore       = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        BottlerocketNodeEC2Describe        = aws_iam_policy.bottlerocket_node_ec2_describe.arn
      }

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 100
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 150
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
    }
  }

  access_entries = {
    bastion = {
      kubernetes_groups = []
      principal_arn     = aws_iam_role.ec2_bastion_role.arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
    # Karpenter node access entry handled by module.karpenter (aws_eks_access_entry.node[0])
  }
}

################################################################################
# Bottlerocket node IAM policy (pluto requires ec2:DescribeInstances)
################################################################################

resource "aws_iam_policy" "bottlerocket_node_ec2_describe" {
  name        = "BottlerocketNodeEC2Describe-${local.resource_name}"
  description = "Allows Bottlerocket pluto service to retrieve instance private DNS name"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

################################################################################
# Karpenter IAM & Infrastructure (SQS, EventBridge)
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.17.1"

  cluster_name = module.eks.cluster_name

  create_node_iam_role          = true
  node_iam_role_name            = "KarpenterNodeRole-${local.resource_name}"
  node_iam_role_use_name_prefix = false
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    BottlerocketNodeEC2Describe  = aws_iam_policy.bottlerocket_node_ec2_describe.arn
  }

  enable_spot_termination = true

  tags = var.tags
}
