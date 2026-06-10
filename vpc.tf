################################################################################
# VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.16.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  # Secondary CIDR for pod subnets (custom networking)
  secondary_cidr_blocks = ["100.64.0.0/16"]

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Node subnets (primary CIDR)
  public_subnets  = ["10.0.0.0/20", "10.0.16.0/20"]
  private_subnets = ["10.0.128.0/20", "10.0.144.0/20"]

  # Pod subnets (secondary CIDR) — used by CNI custom networking
  # /18 per AZ gives ~16k IPs; with prefix delegation each /28 block = 16 IPs
  intra_subnets = ["100.64.0.0/18", "100.64.64.0/18"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Public subnets — for ALB / NLB
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  # Private subnets — EKS nodes primary ENI + internal load balancers
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.cluster_name
  }

  # Intra (pod) subnets — secondary ENIs, pod IPs only
  intra_subnet_tags = {
    "kubernetes.io/role/cni"       = "1"
    "workshop/subnet-type"         = "pod"
  }

  tags = var.tags
}

################################################################################
# Pod Subnet Routes to NAT Gateway
#
# The VPC module's intra_subnets don't get a NAT route by default.
# Pods need outbound internet access to pull images. We add explicit routes
# from each intra subnet route table to the single NAT Gateway.
################################################################################

resource "aws_route" "pod_subnet_nat" {
  count = 2

  route_table_id         = module.vpc.intra_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = module.vpc.natgw_ids[0]

  depends_on = [module.vpc]
}
