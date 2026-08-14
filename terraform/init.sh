#!/bin/bash
set -e

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [SETUP] $1" | tee -a /var/log/setup.log; }

# Update system
log "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install required packages
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
curl -LO "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64"
chmod +x yq_linux_arm64
mv yq_linux_arm64 /usr/local/bin/yq

# Install AWS CLI v2
log "Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip -o awscliv2.zip
./aws/install --update
rm -rf aws awscliv2.zip

# Install Session Manager Plugin
log "Installing SSM Session Manager Plugin..."
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_arm64/session-manager-plugin.deb" -o "session-manager-plugin.deb"
dpkg -i session-manager-plugin.deb
rm -f session-manager-plugin.deb

# Install kubectl
log "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install helm
log "Installing helm..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh
rm -f get_helm.sh

# Install eksctl
log "Installing eksctl..."
ARCH=arm64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
tar -xzf "eksctl_$PLATFORM.tar.gz" -C /usr/local/bin
rm -f "eksctl_$PLATFORM.tar.gz"

# Install k9s
log "Installing k9s..."
curl -LO "https://github.com/derailed/k9s/releases/download/v0.50.18/k9s_Linux_arm64.tar.gz"
tar -xzf k9s_Linux_arm64.tar.gz
chmod +x k9s
mv k9s /usr/local/bin/
rm -f k9s_Linux_arm64.tar.gz LICENSE README.md

# Install kubectx
log "Installing kubectx..."
curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/v0.11.0/kubectx_v0.11.0_linux_arm64.tar.gz" -o kubectx.tar.gz
tar -xzf kubectx.tar.gz kubectx
mv kubectx /usr/local/bin/
rm -f kubectx.tar.gz

# Install stern (multi-pod log tailing)
log "Installing stern..."
curl -fsSL "https://github.com/stern/stern/releases/download/v1.34.0/stern_1.34.0_linux_arm64.tar.gz" -o stern.tar.gz
tar -xzf stern.tar.gz stern
chmod +x stern
mv stern /usr/local/bin/
rm -f stern.tar.gz

# Install Docker
log "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Start and enable Docker service
systemctl start docker
systemctl enable docker

# Setup Docker login in crontab for ubuntu user
cat > /home/ubuntu/docker-login.sh << 'EOF'
#!/bin/bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=ap-southeast-3
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
EOF

chmod +x /home/ubuntu/docker-login.sh
chown ubuntu:ubuntu /home/ubuntu/docker-login.sh

# Add Docker login to crontab (runs every 6 hours to refresh ECR token)
(crontab -u ubuntu -l 2>/dev/null; echo "0 */6 * * * /home/ubuntu/docker-login.sh >> /var/log/docker-login.log 2>&1") | crontab -u ubuntu -

# Configure kubectl for EKS
mkdir -p /home/ubuntu/.kube
chown ubuntu:ubuntu /home/ubuntu/.kube

cat > /home/ubuntu/configure-kubectl.sh << 'EOF'
#!/bin/bash
aws eks update-kubeconfig --region ap-southeast-3 --name eks-default
kubectl get nodes
EOF

chmod +x /home/ubuntu/configure-kubectl.sh
chown ubuntu:ubuntu /home/ubuntu/configure-kubectl.sh

# Create useful aliases
cat >> /home/ubuntu/.bashrc << 'EOF'

# Kubernetes aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgs='kubectl get services'
alias kgn='kubectl get nodes'
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

# Docker aliases
alias d='docker'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dimg='docker images'
alias dlog='docker logs'
alias dex='docker exec -it'

# AWS aliases
alias awsprofile='aws configure list'
alias awswho='aws sts get-caller-identity'

# Stern alias
alias slogs='stern'
EOF

# Set up bash completion
cat >> /home/ubuntu/.bashrc << 'EOF'

# Completions
source <(kubectl completion bash)
complete -F __start_kubectl k
source <(helm completion bash)
source <(eksctl completion bash)
EOF

# Create welcome message
cat > /etc/motd << 'EOF'
################################################################################
#                                                                              #
#                        EKS Bastion Host                                      #
#                                                                              #
#  This server provides access to the private EKS cluster.                     #
#                                                                              #
#  Available tools:                                                            #
#  - kubectl / k9s    (k8s client / dashboard)                                 #
#  - helm / eksctl    (k8s package manager / EKS management)                   #
#  - kubectx / kubens (context & namespace switching)                          #
#  - stern            (multi-pod log tailing)                                  #
#  - aws cli / ssm    (AWS command line & session manager)                     #
#  - docker           (container runtime)                                      #
#  - jq / yq          (JSON & YAML processors)                                #
#  - karpenter        (node autoscaler - deployed via init)                    #
#                                                                              #
#  Quick start:                                                                #
#  - Configure kubectl:  ./configure-kubectl.sh                                #
#  - K9s dashboard:      k9s                                                   #
#  - Docker ECR login:   ./docker-login.sh                                     #
#  - Switch namespace:   kns <namespace>                                       #
#  - Tail pod logs:      stern <pod-name-pattern>                              #
#  - Reinstall Karpenter: ./install-karpenter.sh                               #
#                                                                              #
################################################################################
EOF

################################################################################
# Karpenter Installation (runs from bastion inside VPC)
################################################################################

log "Configuring kubectl for Karpenter installation..."
sudo -u ubuntu aws eks update-kubeconfig --region ap-southeast-3 --name eks-default


# Create Karpenter install script (can be re-run manually if needed)
cat > /home/ubuntu/install-karpenter.sh << 'KARPENTER_SCRIPT'
#!/bin/bash
set -e

CLUSTER_NAME="eks-default"
AWS_REGION="ap-southeast-3"
KARPENTER_VERSION="1.14.0"

echo "==> Configuring kubectl..."
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

echo "==> Installing Karpenter CRDs..."
kubectl apply --server-side -f "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.sh_nodepools.yaml"
kubectl apply --server-side -f "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.k8s.aws_ec2nodeclasses.yaml"
kubectl apply --server-side -f "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.sh_nodeclaims.yaml"

echo "==> Deploying Karpenter via Helm..."
helm registry logout public.ecr.aws || true

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

echo "==> Cloning eks-cni-custom-network repo for manifests..."
git clone https://github.com/mrofisr/eks-cni-custom-network.git /home/ubuntu/eks-cni-custom-network

echo "==> Applying gp3 default StorageClass..."
kubectl apply -f /home/ubuntu/eks-cni-custom-network/manifests/storageclass-gp3.yaml

echo "==> Applying EC2NodeClass and NodePools..."
kubectl apply -f /home/ubuntu/eks-cni-custom-network/manifests/karpenter-nodeclass.yaml
kubectl apply -f /home/ubuntu/eks-cni-custom-network/manifests/karpenter-nodepools.yaml

echo "==> Deploying Demo Retail App Workloads & Public LoadBalancer..."
kubectl apply -f /home/ubuntu/eks-cni-custom-network/manifests/demo-retail-app.yaml

echo "==> Karpenter installation complete!"
echo "==> Verify: kubectl get nodepools,ec2nodeclasses"
echo "==> Logs: kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller | grep -v DEBUG"
KARPENTER_SCRIPT

chmod +x /home/ubuntu/install-karpenter.sh
chown ubuntu:ubuntu /home/ubuntu/install-karpenter.sh

# Run Karpenter installation as ubuntu user
log "Installing Karpenter..."
sudo -u ubuntu /home/ubuntu/install-karpenter.sh >> /var/log/setup.log 2>&1 || log "WARNING: Karpenter install failed - run manually: ./install-karpenter.sh"

log "Bastion host setup completed successfully"
