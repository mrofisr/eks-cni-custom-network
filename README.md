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

Repositories managed via Terraform with lifecycle rules (keep last 30 tagged images, expire untagged after 7 days):

```
jawaracloud/retail-store-sample-catalog
jawaracloud/retail-store-sample-ui
jawaracloud/mysql
jawaracloud/grafana-alloy
jawaracloud/grafana-grafana
jawaracloud/busybox
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

### 3. Create EC2NodeClass + NodePools

Two NodePools, both ARM64 (Graviton) + Bottlerocket:

- `arm64-app` — stateless workloads, spot + on-demand, categories `c`/`m`/`r`
- `arm64-db` — stateful workloads, on-demand only, memory-optimized `r`,
  tainted so only pods with matching toleration schedule here

```bash
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: "KarpenterNodeRole-${CLUSTER_NAME}"
  amiSelectorTerms:
    - alias: "bottlerocket@latest"
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
  name: arm64-app
spec:
  template:
    metadata:
      labels:
        workload-tier: app
    spec:
      requirements:
        - { key: kubernetes.io/arch,                     operator: In, values: ["arm64"] }
        - { key: kubernetes.io/os,                       operator: In, values: ["linux"] }
        - { key: karpenter.sh/capacity-type,             operator: In, values: ["spot", "on-demand"] }
        - { key: karpenter.k8s.aws/instance-category,    operator: In, values: ["c", "m", "r"] }
        - { key: karpenter.k8s.aws/instance-generation,  operator: Gt, values: ["5"] }
        - { key: karpenter.k8s.aws/instance-size,        operator: In, values: ["xlarge", "2xlarge"] }
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 336h
  limits:
    cpu: 32
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: arm64-db
spec:
  template:
    metadata:
      labels:
        workload-tier: db
        workload-type: database
    spec:
      taints:
        - key: workload-type
          value: database
          effect: NoSchedule
      requirements:
        - { key: kubernetes.io/arch,                     operator: In, values: ["arm64"] }
        - { key: kubernetes.io/os,                       operator: In, values: ["linux"] }
        - { key: karpenter.sh/capacity-type,             operator: In, values: ["on-demand"] }
        - { key: karpenter.k8s.aws/instance-category,    operator: In, values: ["r"] }
        - { key: karpenter.k8s.aws/instance-generation,  operator: Gt, values: ["5"] }
        - { key: karpenter.k8s.aws/instance-size,        operator: In, values: ["xlarge", "2xlarge"] }
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 336h
  limits:
    cpu: 16
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
EOF
```

The `arm64-db` taint (`workload-type=database:NoSchedule`) protects DB nodes
from stateless workloads. Only pods that explicitly tolerate this taint land
here — this prevents spot-interrupt evictions from taking down PVC-backed
StatefulSets and stops noisy neighbours from scheduling next to the database.

### 4. Verify

```bash
kubectl get nodepools
kubectl get ec2nodeclasses
kubectl get nodeclaims
```

## Demo Workloads

The official [AWS Containers Retail Sample](https://github.com/aws-containers/retail-store-sample-app)
(from the AWS EKS Workshop) — two tiers that map 1:1 to the client's on-prem
story: a stateless web/API tier and a stateful database tier.

- `demo-app` — `retail-store-sample-catalog` (Go, multi-arch amd64+arm64) →
  lands on NodePool `arm64-app` (spot allowed)
- `demo-db` — `mysql:8.0` → lands **only** on NodePool `arm64-db` (on-demand,
  `workload-type=database` taint + matching toleration)

### Secret + mysql Service

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: demo-db
type: Opaque
stringData:
  MYSQL_ROOT_PASSWORD: demo-root
  MYSQL_PASSWORD: demo-pass
  MYSQL_DATABASE: catalogdb
  MYSQL_USER: catalog_user
---
apiVersion: v1
kind: Service
metadata:
  name: demo-db
spec:
  selector: { app: demo-db }
  ports:
    - port: 3306
      targetPort: 3306
EOF
```

### App tier (stateless — spot eligible)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  labels: { app: demo-app }
spec:
  replicas: 2
  selector: { matchLabels: { app: demo-app } }
  template:
    metadata:
      labels: { app: demo-app }
    spec:
      nodeSelector:
        workload-tier: app
      containers:
        - name: catalog
          image: public.ecr.aws/aws-containers/retail-store-sample-catalog:1.6.1
          env:
            - name: GIN_MODE
              value: release
            - name: RETAIL_CATALOG_PERSISTENCE_PROVIDER
              value: mysql
            - name: RETAIL_CATALOG_PERSISTENCE_ENDPOINT
              value: demo-db:3306
            - name: RETAIL_CATALOG_PERSISTENCE_PASSWORD
              valueFrom:
                secretKeyRef: { name: demo-db, key: MYSQL_PASSWORD }
            - name: RETAIL_CATALOG_SEARCH_ENABLED
              value: "false"
          resources:
            requests: { cpu: 250m, memory: 512Mi }
            limits:   { cpu: "1",  memory: 1Gi }
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet: { path: /health, port: 8080 }
            initialDelaySeconds: 10
            periodSeconds: 5
EOF
```

### DB tier (stateful — on-demand only, tainted)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-db
  labels: { app: demo-db }
spec:
  replicas: 1
  selector: { matchLabels: { app: demo-db } }
  template:
    metadata:
      labels: { app: demo-db }
    spec:
      nodeSelector:
        workload-type: database
      tolerations:
        - key: workload-type
          value: database
          operator: Equal
          effect: NoSchedule
      containers:
        - name: mysql
          image: public.ecr.aws/docker/library/mysql:8.0
          envFrom:
            - secretRef:
                name: demo-db
          env:
            - name: MYSQL_ALLOW_EMPTY_PASSWORD
              value: "true"
          args:
            - --disable-log-bin
          resources:
            requests: { cpu: 500m, memory: 1Gi }
            limits:   { cpu: "1",  memory: 1Gi }
          ports:
            - containerPort: 3306
EOF
```

**Narrasi demo:** `demo-app` (catalog) mendarat di NodePool `arm64-app` —
dibolehkan spot. `demo-db` (mysql) **hanya** bisa mendarat di node ber-taint
`workload-type=database` karena membawa toleration yang cocok — pod app tidak
akan pernah nyasar ke node db, dan db tidak pernah kena eviction spot
interrupt. Catalog akan CrashLoopBackOff sampai mysql Ready — ini menunjukkan
dependency antar tier secara live.

### Verify tiering

```bash
# app pods on arm64-app nodes
kubectl get pods -l app=demo-app -o wide

# db pod on arm64-db node (tainted)
kubectl get pods -l app=demo-db -o wide

# node -> nodepool mapping
kubectl get nodes -L karpenter.sh/nodepool,workload-type,kubernetes.io/arch

# Karpenter provisioning trail
kubectl get nodeclaims

# the money shot — real JSON products from the API
kubectl exec deploy/demo-app -- curl -s http://localhost:8080/catalogue | head -c 200
```

Expected: `demo-app` pods land on nodes labelled `karpenter.sh/nodepool=arm64-app`;
`demo-db` pod lands on a node labelled `karpenter.sh/nodepool=arm64-db` with the
`workload-type=database` taint. Pod IPs are in the secondary CIDR (`100.64.x.x`),
node IPs in the primary CIDR (`10.0.x.x`).

Cleanup:

```bash
kubectl delete deployment demo-app demo-db
kubectl delete service demo-db
kubectl delete secret demo-db
```
