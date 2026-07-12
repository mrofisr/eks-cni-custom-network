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
