#!/bin/bash
set -e

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [SETUP] $1" | tee -a /var/log/setup.log; }

log "Starting bastion host setup..."

# Update system
log "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install base packages
log "Installing base packages..."
apt-get install -y \
    curl \
    unzip \
    git \
    vim \
    htop \
    jq \
    bash-completion \
    net-tools \
    dnsutils \
    traceroute \
    nmap \
    telnet \
    wget

# Install yq (YAML processor)
log "Installing yq..."
curl -sLO "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64"
chmod +x yq_linux_arm64
mv yq_linux_arm64 /usr/local/bin/yq

# Install AWS CLI v2
log "Installing AWS CLI v2..."
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip -o awscliv2.zip
./aws/install --update
rm -rf aws awscliv2.zip

# Install SSM Session Manager Plugin
log "Installing SSM Session Manager Plugin..."
curl -s "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_arm64/session-manager-plugin.deb" -o "session-manager-plugin.deb"
dpkg -i session-manager-plugin.deb
rm -f session-manager-plugin.deb

# Install kubectl (latest stable)
log "Installing kubectl..."
curl -sLO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install helm
log "Installing helm..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm -f get_helm.sh

# Install eksctl
log "Installing eksctl..."
PLATFORM="Linux_arm64"
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_${PLATFORM}.tar.gz"
tar -xzf "eksctl_${PLATFORM}.tar.gz" -C /usr/local/bin
rm -f "eksctl_${PLATFORM}.tar.gz"

# Install k9s
log "Installing k9s..."
curl -sLO "https://github.com/derailed/k9s/releases/download/v0.50.18/k9s_Linux_arm64.tar.gz"
tar -xzf k9s_Linux_arm64.tar.gz k9s
chmod +x k9s
mv k9s /usr/local/bin/
rm -f k9s_Linux_arm64.tar.gz

# Install kubectx + kubens
log "Installing kubectx..."
curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/v0.9.5/kubectx_v0.9.5_linux_arm64.tar.gz" -o kubectx.tar.gz
tar -xzf kubectx.tar.gz kubectx
mv kubectx /usr/local/bin/
rm -f kubectx.tar.gz

curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/v0.9.5/kubens_v0.9.5_linux_arm64.tar.gz" -o kubens.tar.gz
tar -xzf kubens.tar.gz kubens
mv kubens /usr/local/bin/
rm -f kubens.tar.gz

# Install stern (multi-pod log tailing)
log "Installing stern..."
curl -fsSL "https://github.com/stern/stern/releases/download/v1.34.0/stern_1.34.0_linux_arm64.tar.gz" -o stern.tar.gz
tar -xzf stern.tar.gz stern
chmod +x stern
mv stern /usr/local/bin/
rm -f stern.tar.gz

# Configure kubectl for EKS
mkdir -p /home/ubuntu/.kube
chown ubuntu:ubuntu /home/ubuntu/.kube

cat > /home/ubuntu/configure-kubectl.sh << 'EOF'
#!/bin/bash
# Run this after the bastion starts to connect kubectl to the EKS cluster
CLUSTER_NAME=$(aws eks list-clusters --region ap-southeast-3 --query 'clusters[0]' --output text)
aws eks update-kubeconfig --region ap-southeast-3 --name "$CLUSTER_NAME"
echo "Connected to cluster: $CLUSTER_NAME"
kubectl get nodes
EOF

chmod +x /home/ubuntu/configure-kubectl.sh
chown ubuntu:ubuntu /home/ubuntu/configure-kubectl.sh

# Karpenter install script (run after ENIConfig is applied and nodes are cycled)
cat > /home/ubuntu/install-karpenter.sh << 'KARPENTER_SCRIPT'
#!/bin/bash
set -e

CLUSTER_NAME=$(aws eks list-clusters --region ap-southeast-3 --query 'clusters[0]' --output text)
AWS_REGION="ap-southeast-3"
KARPENTER_VERSION="1.11.1"

echo "==> Configuring kubectl..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "==> Installing Karpenter CRDs..."
kubectl apply --server-side \
  -f "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.sh_nodepools.yaml"
kubectl apply --server-side \
  -f "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.k8s.aws_ec2nodeclasses.yaml"
kubectl apply --server-side \
  -f "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.sh_nodeclaims.yaml"

echo "==> Installing Karpenter via Helm..."
KARPENTER_ROLE_ARN=$(aws iam get-role --role-name "karpenter-${CLUSTER_NAME}" --query 'Role.Arn' --output text 2>/dev/null || \
  aws cloudformation describe-stacks --query "Stacks[?contains(StackName,'karpenter')].Outputs[?OutputKey=='KarpenterControllerRoleArn'].OutputValue" --output text)

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace kube-system \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set controller.resources.requests.cpu=100m \
  --set controller.resources.requests.memory=256Mi \
  --wait

echo "==> Karpenter installed. Verify: kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter"
KARPENTER_SCRIPT

chmod +x /home/ubuntu/install-karpenter.sh
chown ubuntu:ubuntu /home/ubuntu/install-karpenter.sh

# Shell aliases and completions for ubuntu user
cat >> /home/ubuntu/.bashrc << 'EOF'

# Kubernetes aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgpo='kubectl get pods -o wide'
alias kgs='kubectl get services'
alias kgn='kubectl get nodes'
alias kgno='kubectl get nodes -o wide'
alias kgi='kubectl get ingress'
alias kdp='kubectl describe pod'
alias kds='kubectl describe service'
alias klog='kubectl logs -f'
alias kex='kubectl exec -it'
alias kaf='kubectl apply -f'
alias kdf='kubectl delete -f'
alias kns='kubens'
alias kctx='kubectx'

# Helm aliases
alias hls='helm list -A'
alias hst='helm status'
alias hh='helm history'

# AWS aliases
alias awswho='aws sts get-caller-identity'

# Stern alias
alias slogs='stern'

# Completions
source <(kubectl completion bash)
complete -F __start_kubectl k
source <(helm completion bash)
source <(eksctl completion bash)
EOF

chown ubuntu:ubuntu /home/ubuntu/.bashrc

# MOTD
cat > /etc/motd << 'EOF'
################################################################################
#                                                                              #
#              EKS CNI Custom Network + Prefix Delegation Workshop             #
#                                                                              #
#  Tools available:                                                            #
#  - kubectl / k9s     (k8s client / terminal UI)                              #
#  - helm / eksctl     (package manager / EKS CLI)                             #
#  - kubectx / kubens  (context & namespace switching)                         #
#  - stern             (multi-pod log tailing)                                 #
#  - aws cli           (AWS CLI v2)                                            #
#  - jq / yq           (JSON & YAML processors)                               #
#                                                                              #
#  Workshop steps:                                                             #
#  1. ./configure-kubectl.sh        — connect kubectl to EKS                   #
#  2. kubectl apply -f ~/manifests/eniconfig.yaml  — apply ENIConfig           #
#  3. Scale node group to 0 then back up           — cycle nodes               #
#  4. kubectl apply -f ~/manifests/demo-deployment.yaml                        #
#  5. kubectl get pods -o wide      — observe 100.64.x.x pod IPs               #
#                                                                              #
################################################################################
EOF

log "Bastion host setup completed successfully"
