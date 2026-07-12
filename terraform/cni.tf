################################################################################
# VPC CNI Addon - Custom Networking + Prefix Delegation + Pod ENI
################################################################################

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = module.eks.cluster_name
  addon_name   = "vpc-cni"

  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
    env = {
      AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
      ENI_CONFIG_LABEL_DEF               = "topology.kubernetes.io/zone"
      ENABLE_PREFIX_DELEGATION           = "true"
      ENABLE_POD_ENI                     = "true"
      WARM_PREFIX_TARGET                 = "1"
    }
    init = {
      config = {
        DISABLE_TCP_EARLY_DEMUX = "true"
      }
    }
  })

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [module.eks]

  tags = var.tags
}

################################################################################
# ENIConfig CRDs (one per AZ - maps to intra subnets)
################################################################################

resource "kubernetes_manifest" "eniconfig" {
  for_each = { for idx, az in data.aws_availability_zones.available.names : az => idx }

  manifest = {
    apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
    kind       = "ENIConfig"
    metadata = {
      name = each.key
    }
    spec = {
      subnet = module.vpc.intra_subnets[each.value]
      securityGroups = [
        module.eks.node_security_group_id
      ]
    }
  }

  depends_on = [aws_eks_addon.vpc_cni]
}

################################################################################
# SecurityGroupPolicy CRD (pod-level security groups)
################################################################################

resource "kubernetes_manifest" "security_group_policy" {
  manifest = {
    apiVersion = "vpcresources.k8s.aws/v1beta1"
    kind       = "SecurityGroupPolicy"
    metadata = {
      name      = "${var.cluster_name}-default-sgp"
      namespace = "default"
    }
    spec = {
      podSelector = {}
      securityGroups = {
        groupIds = [
          module.eks.node_security_group_id
        ]
      }
    }
  }

  depends_on = [aws_eks_addon.vpc_cni]
}
