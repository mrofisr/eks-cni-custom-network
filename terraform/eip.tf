################################################################################
# Gateway Elastic IPs (one per AZ for NLB)
################################################################################

resource "aws_eip" "gateway" {
  count = length(data.aws_availability_zones.available.names)

  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-gateway-eip-${data.aws_availability_zones.available.names[count.index]}"
  })
}
