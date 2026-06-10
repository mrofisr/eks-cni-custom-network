# EKS CNI Custom Network + Prefix Delegation Workshop

A hands-on workshop demonstrating EKS CNI custom networking with prefix delegation on AWS.

**What you'll learn:**
- How CNI custom networking separates pod IPs from node IPs using a secondary VPC CIDR
- How prefix delegation (`/28` blocks) multiplies pod density per node
- How `ENIConfig` maps each AZ to a dedicated pod subnet

---

## Architecture

```
VPC: 10.0.0.0/16 (nodes) + 100.64.0.0/16 (pods)

AZ-a                              AZ-b
├── Public  10.0.0.0/20           ├── Public  10.0.16.0/20
├── Private 10.0.128.0/20  ←nodes ├── Private 10.0.144.0/20  ←nodes
└── Pod     100.64.0.0/18  ←pods  └── Pod     100.64.64.0/18 ←pods
```

Node IPs come from `10.0.128.0/20` or `10.0.144.0/20`.
Pod IPs come from `100.64.0.0/18` or `100.64.64.0/18`.

---

## Prerequisites

- AWS account with sufficient permissions (EKS, VPC, IAM, EC2)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.7
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- An S3 bucket for Terraform state (or remove the backend block to use local state)

---

## Step 1 — Configure backend

Edit `main.tf` and fill in your S3 backend:

```hcl
backend "s3" {
  bucket  = "your-tfstate-bucket"
  profile = "your-aws-profile"
  ...
}
```

---

## Step 2 — Deploy infrastructure

```bash
terraform init
terraform plan
terraform apply
```

This creates:
- VPC with dual CIDR (nodes + pods)
- EKS cluster with `vpc-cni` configured for custom networking + prefix delegation
- Bootstrap managed node group (runs CoreDNS, kube-proxy)
- Bastion host (access via SSM Session Manager)

---

## Step 3 — Connect to bastion

```bash
# Get bastion instance ID
BASTION_ID=$(terraform output -raw bastion_instance_id)

# Connect via SSM (no SSH key or public IP needed)
aws ssm start-session --target "$BASTION_ID" --region ap-southeast-3
```

Once inside the bastion:

```bash
./configure-kubectl.sh
kubectl get nodes
```

---

## Step 4 — Apply ENIConfig

Get the values from Terraform:

```bash
terraform output workshop_eniconfig_hint
```

Edit `manifests/eniconfig.yaml` replacing the placeholder values, then apply:

```bash
kubectl apply -f manifests/eniconfig.yaml
kubectl get eniconfigs
```

Expected output:
```
NAME              AGE
ap-southeast-3a   5s
ap-southeast-3b   5s
```

---

## Step 5 — Cycle nodes

Existing nodes don't pick up ENIConfig — only new nodes do. Scale the node group to 0 then back up:

```bash
CLUSTER=$(terraform output -raw eks_cluster_name)

# Scale down
aws eks update-nodegroup-config \
  --cluster-name "$CLUSTER" \
  --nodegroup-name bootstrap-nodes \
  --scaling-config minSize=0,maxSize=3,desiredSize=0 \
  --region ap-southeast-3

# Wait for all nodes to terminate
kubectl get nodes -w

# Scale back up
aws eks update-nodegroup-config \
  --cluster-name "$CLUSTER" \
  --nodegroup-name bootstrap-nodes \
  --scaling-config minSize=1,maxSize=3,desiredSize=2 \
  --region ap-southeast-3

# Wait for nodes to be Ready
kubectl get nodes -w
```

---

## Step 6 — Verify pod IPs

```bash
kubectl get nodes -o wide
```

Node IPs should be in `10.0.128.0/20` or `10.0.144.0/20`.

---

## Step 7 — Deploy demo workload

```bash
kubectl apply -f manifests/demo-deployment.yaml

# Scale up to see prefix delegation in action
kubectl scale deployment nginx-prefix-demo --replicas=50

# Watch pods come up
kubectl get pods -o wide -w
```

All pod IPs should be in the `100.64.0.0/16` range.

**This is the "aha moment"** — node IPs and pod IPs are completely separate CIDRs.

---

## Step 8 — Verify prefix delegation

On a node, check the ENI prefixes assigned:

```bash
# Get a node name
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# Describe the node — look for max-pods annotation
kubectl describe node "$NODE" | grep -E "pods|prefix"

# From the bastion, check ENI prefixes via AWS CLI
aws ec2 describe-network-interfaces \
  --filters "Name=attachment.instance-id,Values=$(kubectl get node $NODE -o jsonpath='{.spec.providerID}' | cut -d/ -f5)" \
  --query 'NetworkInterfaces[*].Ipv4Prefixes' \
  --region ap-southeast-3
```

Each `/28` prefix covers 16 pod IPs. With prefix delegation a `t4g.xlarge` can
run far more pods than the 58-pod limit without it.

---

## Step 9 — Install Karpenter (optional)

```bash
./install-karpenter.sh
```

Karpenter will provision workload nodes with the same CNI custom networking —
new Karpenter nodes automatically pick up ENIConfig via the AZ label.

---

## Cleanup

```bash
kubectl delete -f manifests/demo-deployment.yaml
terraform destroy
```

---

## Key concepts

| Concept | What it does |
|---------|-------------|
| CNI custom networking | Pods use secondary ENIs on pod subnets, not the node's primary ENI subnet |
| `ENIConfig` | Maps each AZ to a specific pod subnet + security group |
| `ENI_CONFIG_LABEL_DEF` | Tells the CNI which node label to use to pick the correct ENIConfig |
| Prefix delegation | Assigns `/28` blocks (16 IPs) per ENI slot instead of 1 IP — increases pod density |
| `WARM_PREFIX_TARGET` | Keeps spare `/28` prefixes pre-allocated to reduce pod startup latency |
