################################################################################
# VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  secondary_cidr_blocks = var.secondary_cidr_blocks

  azs             = data.aws_availability_zones.available.names
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  intra_subnets   = var.intra_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = var.cluster_name
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
    "karpenter.sh/discovery" = var.cluster_name
  }

  intra_subnet_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = var.tags
}

################################################################################
# VPC Interface & Gateway Endpoints (Pillar 01 - Cloud AWS API Connectivity)
################################################################################

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "6.6.1"

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [module.eks.node_security_group_id]

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = concat(module.vpc.private_route_table_ids, module.vpc.intra_route_table_ids)
      tags            = { Name = "${var.cluster_name}-s3-vpc-endpoint" }
    },
    sts = {
      service             = "sts"
      private_dns_enabled = true
      tags                = { Name = "${var.cluster_name}-sts-vpc-endpoint" }
    },
    ecr_api = {
      service             = "ecr.api"
      private_dns_enabled = true
      tags                = { Name = "${var.cluster_name}-ecr-api-vpc-endpoint" }
    },
    ecr_dkr = {
      service             = "ecr.dkr"
      private_dns_enabled = true
      tags                = { Name = "${var.cluster_name}-ecr-dkr-vpc-endpoint" }
    },
    secretsmanager = {
      service             = "secretsmanager"
      private_dns_enabled = true
      tags                = { Name = "${var.cluster_name}-secretsmanager-vpc-endpoint" }
    },
    ec2 = {
      service             = "ec2"
      private_dns_enabled = true
      tags                = { Name = "${var.cluster_name}-ec2-vpc-endpoint" }
    },
    eks = {
      service             = "eks"
      private_dns_enabled = true
      tags                = { Name = "${var.cluster_name}-eks-vpc-endpoint" }
    }
  }

  tags = var.tags
}

################################################################################
# Private NAT Gateway (for intra subnets - CNI custom networking)
################################################################################

resource "aws_nat_gateway" "private" {
  connectivity_type = "private"
  subnet_id         = module.vpc.private_subnets[0]

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-private-nat"
  })
}

resource "aws_route" "intra_default_gateway" {
  route_table_id         = module.vpc.intra_route_table_ids[0]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.private.id

  depends_on = [aws_nat_gateway.private]
}
