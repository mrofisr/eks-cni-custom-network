# EKS CNI Custom Network

Terraform configuration for an EKS cluster with CNI custom networking, Karpenter autoscaling, and a bastion host accessed via SSM Session Manager.

## Architecture

```
                                ┌──────────────────────────┐
                                │    Internet Gateway      │
                                └────────────┬─────────────┘
                                             │
┌────────────────────────────────────────────┼──────────────────────────────────────────────┐
│ VPC (10.0.0.0/16)                          │      Secondary CIDR: 100.64.0.0/16         │
│                                            │                                              │
│  ┌─────────────────────── Public Subnets ──┼───────────────────────────────────────┐      │
│  │                                        │                                       │      │
│  │   ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                           │      │
│  │   │  10.0.101/24  │ │  10.0.102/24  │ │  10.0.103/24  │    Load Balancers       │      │
│  │   │   AZ-a       │ │   AZ-b       │ │   AZ-c       │                           │      │
│  │   └──────────────┘ └──────────────┘ └──────────────┘                           │      │
│  └─────────────────────────────────────────────────────────────────────────────────┘      │
│           │                                                                                │
│  ┌────────┼─────── Private Subnets ─────────────────────────────────────────────────┐     │
│  │        │                                                                        │     │
│  │   ┌────▼──────────┐ ┌──────────────┐ ┌──────────────┐                          │     │
│  │   │   10.0.1/24    │ │   10.0.2/24   │ │   10.0.3/24   │   ◄── NAT Gateway       │     │
│  │   │   AZ-a        │ │   AZ-b        │ │   AZ-c        │                          │     │
│  │   │              │ │              │ │              │                          │     │
│  │   │  ┌────────┐  │ │  ┌────────┐  │ │  ┌────────┐  │                          │     │
│  │   │  │ EKS    │  │ │  │ EKS    │  │ │  │ EKS    │  │   ◄── Karpenter Nodes    │     │
│  │   │  │ Node   │  │ │  │ Node   │  │ │  │ Node   │  │      (Spot/On-Demand)    │     │
│  │   │  └────────┘  │ │  └────────┘  │ │  └────────┘  │                          │     │
│  │   │              │ │              │ │              │                          │     │
│  │   │  ┌────────┐  │ │              │ │              │                          │     │
│  │   │  │Bastion │  │ │              │ │              │   ◄── SSM Session Mgr     │     │
│  │   │  │ (EC2)  │  │ │              │ │              │      (no public IP)       │     │
│  │   │  └────────┘  │ │              │ │              │                          │     │
│  │   └──────────────┘ └──────────────┘ └──────────────┘                          │     │
│  └─────────────────────────────────────────────────────────────────────────────────┘     │
│           │                                                                                │
│  ┌────────┼─────── Intra Subnets ─── CNI Custom Networking ─────────────────────────┐    │
│  │        │                                                                        │    │
│  │   ┌────▼──────────┐ ┌──────────────┐ ┌──────────────┐                          │    │
│  │   │  100.64.1/24   │ │  100.64.2/24  │ │  100.64.3/24  │   ◄── Private NAT       │    │
│  │   │   AZ-a        │ │   AZ-b        │ │   AZ-c        │                          │    │
│  │   │              │ │              │ │              │                          │    │
│  │   │  Pod ENIs    │ │  Pod ENIs    │ │  Pod ENIs    │   ◄── ENIConfig / AZ     │    │
│  │   │  (secondary) │ │  (secondary) │ │  (secondary) │                          │    │
│  │   │              │ │              │ │              │                          │    │
│  │   │  100.64.x.x  │ │  100.64.x.x  │ │  100.64.x.x  │   ◄── Prefix Delegation  │    │
│  │   └──────────────┘ └──────────────┘ └──────────────┘                          │    │
│  └─────────────────────────────────────────────────────────────────────────────────┘    │
│                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────────────────────────┐
  │                              Supporting Services                                        │
  │                                                                                         │
  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
  │   │  ECR (19)   │  │  S3 State   │  │  S3 Data    │  │  EIPs/NLB   │                 │
  │   │  repos      │  │  bucket     │  │  bucket     │  │  (per AZ)   │                 │
  │   └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘                 │
  └─────────────────────────────────────────────────────────────────────────────────────────┘
```

## CNI Custom Networking Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CNI Custom Networking                               │
│                                                                             │
│   Node (private subnet)              Pod (intra subnet)                     │
│  ┌──────────────────────┐           ┌──────────────────────┐               │
│  │                      │           │                      │               │
│  │  eth0                │           │  eth0                │               │
│  │  10.0.x.x            │           │  100.64.x.x          │               │
│  │  (primary ENI)       │           │  (secondary ENI)     │               │
│  │                      │           │                      │               │
│  │  ┌────────────────┐  │  creates  │  ┌────────────────┐  │               │
│  │  │ aws-node       │  │──────────>│  │ ENIConfig      │  │               │
│  │  │ daemonset      │  │  ENI in   │  │ (per AZ)       │  │               │
│  │  │                │  │  intra    │  │                │  │               │
│  │  │ • CUSTOM_NETWORK│  │  subnet  │  │ subnet: intra  │  │               │
│  │  │ • PREFIX_DELEG │  │           │  │ securityGroups │  │               │
│  │  │ • POD_ENI      │  │           │  └────────────────┘  │               │
│  │  └────────────────┘  │           │                      │               │
│  │                      │           │  ┌────────────────┐  │               │
│  │  ┌────────────────┐  │           │  │ SecurityGroup  │  │               │
│  │  │ Pod Identity   │  │           │  │ Policy (CRD)   │  │               │
│  │  │ (IAM for pods) │  │           │  │ pod-level SG   │  │               │
│  │  └────────────────┘  │           │  └────────────────┘  │               │
│  └──────────────────────┘           └──────────────────────┘               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Components

```
  ┌─────────────────────────────────────────────────────────────────────────┐
  │                        Terraform Modules                                │
  │                                                                         │
  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐              │
  │  │  VPC          │  │  EKS          │  │  Karpenter    │              │
  │  │  v6.6.1       │  │  v21.17.1     │  │  v21.17.1     │              │
  │  │               │  │               │  │  (submodule)  │              │
  │  │ • public      │  │ • cluster     │  │               │              │
  │  │ • private     │  │ • node group  │  │ • SQS queue   │              │
  │  │ • intra       │  │ • KMS         │  │ • EventBridge │              │
  │  │ • secondary   │  │ • access      │  │ • node IAM    │              │
  │  │   CIDR        │  │   entries     │  │               │              │
  │  └───────────────┘  └───────────────┘  └───────────────┘              │
  │                                                                         │
  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐              │
  │  │  EC2          │  │  ECR          │  │  S3           │              │
  │  │  v6.4.0       │  │  v3.2.0       │  │  v5.14.1      │              │
  │  │               │  │               │  │               │              │
  │  │ • bastion     │  │ • 19 repos    │  │ • state       │              │
  │  │ • SSM access  │  │ • lifecycle   │  │ • data        │              │
  │  │ • no public IP│  │ • for_each    │  │ • SSE-S3      │              │
  │  └───────────────┘  └───────────────┘  └───────────────┘              │
  │                                                                         │
  └─────────────────────────────────────────────────────────────────────────┘
```

| Module | Source | Version | Purpose |
|--------|--------|---------|---------|
| VPC | `terraform-aws-modules/vpc/aws` | 6.6.1 | VPC with public/private/intra subnets, secondary CIDR |
| EKS | `terraform-aws-modules/eks/aws` | 21.17.1 | EKS cluster, managed node group, KMS encryption |
| Karpenter | `terraform-aws-modules/eks/aws//modules/karpenter` | 21.17.1 | Node autoscaler, SQS, EventBridge |
| EC2 | `terraform-aws-modules/ec2-instance/aws` | 6.4.0 | Bastion host (private subnet, SSM access) |
| ECR | `terraform-aws-modules/ecr/aws` | 3.2.0 | 19 private repositories with lifecycle policies |
| S3 | `terraform-aws-modules/s3-bucket/aws` | 5.14.1 | State bucket + data bucket (SSE-S3, versioned) |

## Prerequisites

```
  ┌─────────────────────────────────────────────────────────────────────────┐
  │                          Prerequisites                                  │
  │                                                                         │
  │   ✓  Terraform >= 1.5.7                                                │
  │   ✓  AWS CLI configured with correct profile                          │
  │   ✓  kubectl for cluster access                                       │
  │   ✓  SSM Session Manager plugin (for bastion access)                  │
  │                                                                         │
  └─────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

```
  ┌─────────────────────────────────────────────────────────────────────────┐
  │                        Quick Start                                      │
  │                                                                         │
  │   $ make init               # Initialize Terraform                     │
  │   $ make plan               # Review the plan                          │
  │   $ make apply              # Apply changes                            │
  │                                                                         │
  │   # Configure kubectl                                                  │
  │   $ aws eks update-kubeconfig \                                        │
  │       --region ap-southeast-3 \                                        │
  │       --name eks-default                                               │
  │                                                                         │
  │   # Access bastion via SSM                                             │
  │   $ aws ssm start-session \                                           │
  │       --target <instance-id>                                           │
  │                                                                         │
  └─────────────────────────────────────────────────────────────────────────┘
```

```bash
# Initialize Terraform
make init

# Review the plan
make plan

# Apply
make apply

# Configure kubectl
aws eks update-kubeconfig --region ap-southeast-3 --name eks-default

# Access bastion via SSM (no public IP)
aws ssm start-session --target $(terraform -chdir=terraform output -raw bastion_instance_id)
```

## File Structure

```
  ┌─────────────────────────────────────────────────────────────────────────┐
  │                        File Structure                                   │
  │                                                                         │
  │   terraform/                                                            │
  │   ├── main.tf          │ Providers, backend, data sources              │
  │   ├── vpc.tf           │ VPC module + private NAT gateway              │
  │   ├── eks.tf           │ EKS cluster + Karpenter                       │
  │   ├── ec2.tf           │ Bastion host (private subnet) + IAM           │
  │   ├── ecr.tf           │ ECR repositories (for_each)                   │
  │   ├── s3.tf            │ S3 buckets (state + data)                     │
  │   ├── cni.tf           │ VPC CNI addon + ENIConfig + SGP               │
  │   ├── iam.tf           │ VPC CNI Pod Identity, Karpenter, Alloy IRSA   │
  │   ├── eip.tf           │ Gateway Elastic IPs per AZ                    │
  │   ├── variables.tf     │ All input variables                           │
  │   ├── outputs.tf       │ All outputs                                   │
  │   └── init.sh          │ Bastion bootstrap script                      │
  │                                                                         │
  │   Makefile             │ Build targets                                 │
  │   README.md            │ This file                                     │
  │                                                                         │
  └─────────────────────────────────────────────────────────────────────────┘
```

## Key Configuration

### CNI Custom Networking

```
  ┌─────────────────────────────────────────────────────────────────────────┐
  │                     VPC CNI Addon Settings                              │
  │                                                                         │
  │   AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = true                            │
  │       └── Pods get IPs from intra subnets (not node subnet)            │
  │                                                                         │
  │   ENABLE_PREFIX_DELEGATION = true                                       │
  │       └── /28 prefixes instead of individual IPs → higher density       │
  │                                                                         │
  │   ENABLE_POD_ENI = true                                                 │
  │       └── Security groups for pods (branch ENIs)                        │
  │                                                                         │
  │   ENI_CONFIG_LABEL_DEF = topology.kubernetes.io/zone                    │
  │       └── AZ-aware ENIConfig selection                                  │
  │                                                                         │
  └─────────────────────────────────────────────────────────────────────────┘
```

### Subnets

```
  ┌─────────────────────────────────────────────────────────────────────────┐
  │                           Subnet Layout                                 │
  │                                                                         │
  │   Type      │ CIDR             │ Purpose                                │
  │   ──────────┼──────────────────┼─────────────────────────────────────── │
  │   Public    │ 10.0.101-103/24  │ Load balancers only                   │
  │   Private   │ 10.0.1-3/24      │ EKS nodes, bastion, NAT gateway       │
  │   Intra     │ 100.64.1-3/24    │ Pod ENIs (CNI custom networking)       │
  │                                                                         │
  └─────────────────────────────────────────────────────────────────────────┘
```

### ECR Repositories

```
  ┌─────────────────────────────────────────────────────────────────────────┐
  │                     ECR Lifecycle Policies                              │
  │                                                                         │
  │   19 repositories under jawaracloud/ namespace                          │
  │                                                                         │
  │   Rule 1:  Keep last 30 images (any tag)                               │
  │   Rule 2:  Expire untagged images after 7 days                         │
  │                                                                         │
  │   Repositories:                                                         │
  │   ├── jawaracloud/genai-*          (11 repos)                           │
  │   ├── jawaracloud/grafana-*        (5 repos)                            │
  │   ├── jawaracloud/prometheus-*     (1 repo)                             │
  │   ├── jawaracloud/busybox          (1 repo)                             │
  │   └── jawaracloud/nginx-*          (1 repo)                             │
  │                                                                         │
  └─────────────────────────────────────────────────────────────────────────┘
```

## Karpenter Setup

After applying Terraform, deploy Karpenter CRDs and NodePool from the bastion host.

> **Docs:** [karpenter.sh/v1.14/getting-started](https://karpenter.sh/v1.14/getting-started/) | [NodePool](https://karpenter.sh/v1.14/concepts/nodepools/) | [EC2NodeClass](https://karpenter.sh/v1.14/concepts/nodeclasses/) | [Disruption](https://karpenter.sh/v1.14/concepts/disruption/)

### 1. Install Karpenter CRDs

```bash
KARPENTER_VERSION="1.14.0"

kubectl apply --server-side -f \
  "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.sh_nodepools.yaml"

kubectl apply --server-side -f \
  "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.k8s.aws_ec2nodeclasses.yaml"

kubectl apply --server-side -f \
  "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.sh_nodeclaims.yaml"
```

### 2. Deploy Karpenter (Helm)

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

### 5. Test (optional)

```bash
kubectl scale deployment inflate --replicas 5
kubectl get nodeclaims -w

kubectl delete deployment inflate
# Karpenter consolidates empty nodes automatically
```

## Commands

```
  ┌─────────────────────────────────────────────────────────────────────────┐
  │                         Makefile Targets                                │
  │                                                                         │
  │   make init         │ Initialize Terraform                             │
  │   make plan         │ Preview changes                                  │
  │   make apply        │ Apply changes                                    │
  │   make destroy      │ Destroy all resources                            │
  │   make fmt          │ Format Terraform files                           │
  │   make validate     │ Validate configuration                           │
  │   make clean        │ Remove .terraform/ and state files               │
  │   make output       │ Show outputs                                     │
  │   make state-list   │ List state resources                             │
  │                                                                         │
  └─────────────────────────────────────────────────────────────────────────┘
```

```bash
make init          # Initialize Terraform
make plan          # Preview changes
make apply         # Apply changes
make destroy       # Destroy all resources
make fmt           # Format Terraform files
make validate      # Validate configuration
make clean         # Remove .terraform/ and state files
make output        # Show outputs
make state-list    # List state resources
```
