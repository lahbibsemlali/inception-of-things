#!/bin/bash

set -e

echo "🚀 Starting IoT Part 3 Setup..."

# Update system
echo "📦 Updating system..."
sudo apt-get update

# Install Docker if not present
if ! command -v docker &>/dev/null; then
  echo "🐳 Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  sudo usermod -aG docker $USER
  rm get-docker.sh
  echo "Docker installed. You may need to log out and back in."
fi

# Install kubectl if not present
if ! command -v kubectl &>/dev/null; then
  echo "☸️  Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
fi

# Install K3d if not present
if ! command -v k3d &>/dev/null; then
  echo "🎮 Installing K3d..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

# Install ArgoCD CLI (optional but useful)
if ! command -v argocd &>/dev/null; then
  echo "🔄 Installing ArgoCD CLI..."
  curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
  rm argocd-linux-amd64
fi

echo "✅ All tools installed!"
echo ""
echo "Versions:"
docker --version
kubectl version --client --short
k3d --version
argocd version --client --short

# Create K3d cluster
echo ""
echo "🏗️  Creating K3d cluster..."
k3d cluster create iot-cluster \
  --port 8080:80@loadbalancer \
  --port 8888:8888@loadbalancer \
  --port 8443:443@loadbalancer

# Wait for cluster to be ready
echo "⏳ Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=60s

echo "✅ Cluster created successfully!"
kubectl get nodes
