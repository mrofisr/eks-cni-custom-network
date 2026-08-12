# EKS CNI Custom Network

Terraform configuration for an EKS cluster with CNI custom networking, Karpenter autoscaling, and a bastion host accessed via SSM Session Manager.

## Architecture

```
                          Internet Gateway
                                 │
┌────────────────────────────────┼────────────────────────────────┐
│ VPC 10.0.0.0/16                │   Secondary CIDR 100.64.0.0/16 │
│                                │                                │
│  Public Subnets (Load Balancers only)                           │
│  ├── 10.0.101.0/24  AZ-a                                        │
│  ├── 10.0.102.0/24  AZ-b                                        │
│  └── 10.0.103.0/24  AZ-c                                        │
│          │ NAT Gateway                                          │
│  Private Subnets (EKS nodes, bastion)                           │
│  ├── 10.0.1.0/24  AZ-a  ── EKS Node, Bastion (SSM only)        │
│  ├── 10.0.2.0/24  AZ-b  ── EKS Node                            │
│  └── 10.0.3.0/24  AZ-c  ── EKS Node                            │
│          │ Private NAT                                          │
│  Intra Subnets (Pod ENIs via CNI custom networking)             │
│  ├── 100.64.1.0/24  AZ-a  ── ENIConfig / Pod IPs               │
│  ├── 100.64.2.0/24  AZ-b  ── ENIConfig / Pod IPs               │
│  └── 100.64.3.0/24  AZ-c  ── ENIConfig / Pod IPs               │
└─────────────────────────────────────────────────────────────────┘
```

## CNI Custom Networking

Pods get IPs from the intra subnets (100.64.x.x), not from the node's subnet. The `aws-node` daemonset creates a secondary ENI in the intra subnet for each node, and ENIConfig selects the right subnet per AZ.

```
Node (10.0.x.x, private subnet)          Pod (100.64.x.x, intra subnet)
  eth0 = primary ENI                        eth0 = secondary ENI
  aws-node daemonset  ──creates ENI──>      ENIConfig (per AZ)
    CUSTOM_NETWORK_CFG = true               subnet: intra
    PREFIX_DELEGATION  = true               securityGroups: pod-level SGP
    POD_ENI            = true
    ENI_CONFIG_LABEL   = topology zone
```

## Modules

| Module | Version | Purpose |
|--------|---------|---------|
| `terraform-aws-modules/vpc/aws` | 6.6.1 | VPC with public/private/intra subnets, secondary CIDR |
| `terraform-aws-modules/eks/aws` | 21.17.1 | EKS cluster, managed node group, KMS encryption |
| `terraform-aws-modules/eks/aws//modules/karpenter` | 21.17.1 | Node autoscaler, SQS, EventBridge |
| `terraform-aws-modules/ec2-instance/aws` | 6.4.0 | Bastion host (private subnet, SSM access) |
| `terraform-aws-modules/ecr/aws` | 3.2.0 | 19 private repositories with lifecycle policies |
| `terraform-aws-modules/s3-bucket/aws` | 5.14.1 | State bucket + data bucket (SSE-S3, versioned) |

## File Structure

```
terraform/
├── main.tf        providers, backend, data sources
├── vpc.tf         VPC module + private NAT gateway
├── eks.tf         EKS cluster + Karpenter
├── ec2.tf         bastion host + IAM
├── ecr.tf         ECR repositories (for_each)
├── s3.tf          S3 buckets (state + data)
├── cni.tf         VPC CNI addon + ENIConfig + SGP
├── iam.tf         Pod Identity, Karpenter, Alloy IRSA
├── eip.tf         gateway Elastic IPs per AZ
├── variables.tf
└── outputs.tf
Makefile
```

## Prerequisites

- Terraform >= 1.5.7
- AWS CLI configured with correct profile
- kubectl
- SSM Session Manager plugin (for bastion access)

## Quick Start

```bash
make init
make plan
make apply

# Configure kubectl
aws eks update-kubeconfig --region ap-southeast-3 --name eks-default

# Access bastion via SSM (no public IP)
aws ssm start-session --target $(terraform -chdir=terraform output -raw bastion_instance_id)
```

## Makefile Targets

```
make init          initialize Terraform
make plan          preview changes
make apply         apply changes
make destroy       destroy all resources
make fmt           format Terraform files
make validate      validate configuration
make clean         remove .terraform/ and state files
make output        show outputs
make state-list    list state resources
```

## ECR Repositories

19 repositories under `jawaracloud/` with lifecycle rules: keep last 30 tagged images, expire untagged after 7 days.

```
jawaracloud/ai-*          (11 repos)
jawaracloud/grafana-*     (5 repos)
jawaracloud/prometheus-*  (1 repo)
jawaracloud/busybox        (1 repo)
jawaracloud/nginx-*        (1 repo)
```

## Karpenter Setup

Deploy after `make apply`, from the bastion or any kubectl-configured machine.

### 1. Install CRDs

```bash
KARPENTER_VERSION="1.14.0"

kubectl apply --server-side -f \
  "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.sh_nodepools.yaml"
kubectl apply --server-side -f \
  "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.k8s.aws_ec2nodeclasses.yaml"
kubectl apply --server-side -f \
  "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.sh_nodeclaims.yaml"
```

### 2. Deploy via Helm

```bash
CLUSTER_NAME="eks-default"
AWS_REGION="ap-southeast-3"

helm registry logout public.ecr.aws

helm upgrade --install karpenter \
  oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace kube-system --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait
```

### 3. Create EC2NodeClass + NodePool

```bash
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: "KarpenterNodeRole-${CLUSTER_NAME}"
  amiSelectorTerms:
    - alias: "al2023@latest"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r", "t"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 720h
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
EOF
```

### 4. Verify

```bash
kubectl get nodepools
kubectl get ec2nodeclasses
kubectl get nodeclaims
```
