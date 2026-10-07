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
# Applied via bastion init.sh after cluster is ready — not via Terraform
# kubernetes_manifest requires a live cluster endpoint at plan time.
################################################################################

resource "null_resource" "eniconfig" {
  for_each = { for idx, az in data.aws_availability_zones.available.names : az => idx }

  triggers = {
    az     = each.key
    subnet = module.vpc.intra_subnets[each.value]
    sg     = module.eks.node_security_group_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name} 2>/dev/null || true
      kubectl apply -f - <<EOF
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: ${each.key}
spec:
  subnet: ${module.vpc.intra_subnets[each.value]}
  securityGroups:
    - ${module.eks.node_security_group_id}
EOF
    EOT
  }

  depends_on = [aws_eks_addon.vpc_cni]
}

################################################################################
# SecurityGroupPolicy CRD (pod-level security groups)
# Applied via bastion init.sh after cluster is ready — same reason as above.
################################################################################

resource "null_resource" "security_group_policy" {
  triggers = {
    cluster = module.eks.cluster_name
    sg      = module.eks.node_security_group_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name} 2>/dev/null || true
      kubectl apply -f - <<EOF
apiVersion: vpcresources.k8s.aws/v1beta1
kind: SecurityGroupPolicy
metadata:
  name: ${local.resource_name}-default-sgp
  namespace: default
spec:
  podSelector: {}
  securityGroups:
    groupIds:
      - ${module.eks.node_security_group_id}
EOF
    EOT
  }

  depends_on = [aws_eks_addon.vpc_cni]
}
