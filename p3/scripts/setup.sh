#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_status() {
    echo -e "${GREEN}[*]${NC} $1"
}

print_error() {
    echo -e "${RED}[!]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Update system
update_system() {
    print_status "Updating system packages..."
    sudo apt-get update
    sudo apt-get upgrade -y
}

# Install Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        print_status "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        rm get-docker.sh
        print_status "Docker installed successfully"
    else
        print_status "Docker already installed"
    fi
}

# Install kubectl
install_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_status "Installing kubectl..."
        KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
        curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
        print_status "kubectl installed successfully"
    else
        print_status "kubectl already installed"
    fi
}

# Install k3d
install_k3d() {
    if ! command -v k3d &> /dev/null; then
        print_status "Installing K3d..."
        wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
        print_status "K3d installed successfully"
    else
        print_status "K3d already installed"
    fi
}

# Install git
install_git() {
    if ! command -v git &> /dev/null; then
        print_status "Installing git..."
        sudo apt-get install -y git
        print_status "git installed successfully"
    else
        print_status "git already installed"
    fi
}

# Install curl
install_curl() {
    if ! command -v curl &> /dev/null; then
        print_status "Installing curl..."
        sudo apt-get install -y curl
        print_status "curl installed successfully"
    else
        print_status "curl already installed"
    fi
}

# Create k3d cluster
create_k3d_cluster() {
    CLUSTER_NAME="iot-cluster"
    
    if k3d cluster list | grep -q $CLUSTER_NAME; then
        print_warning "Cluster $CLUSTER_NAME already exists, deleting..."
        k3d cluster delete $CLUSTER_NAME
        sleep 5
    fi
    
    print_status "Creating K3d cluster: $CLUSTER_NAME"
    k3d cluster create $CLUSTER_NAME \
        --servers 1 \
        --agents 2 \
        -p "80:80@loadbalancer" \
        -p "443:443@loadbalancer" \
        -p "8888:8888@loadbalancer" \
        --wait
    
    print_status "Merging kubeconfig..."
    k3d kubeconfig merge $CLUSTER_NAME -d -s
    
    print_status "Verifying cluster setup..."
    kubectl cluster-info
    print_status "Cluster nodes:"
    kubectl get nodes
}

# Create namespaces
create_namespaces() {
    print_status "Creating argocd namespace..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    print_status "Creating dev namespace..."
    kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
    
    print_status "Namespaces created:"
    kubectl get namespaces
}

# Install Argo CD
install_argocd() {
    print_status "Installing Argo CD in argocd namespace..."
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    print_status "Waiting for Argo CD to be ready (this may take 1-2 minutes)..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd 2>/dev/null || true
    
    sleep 10
    
    print_status "Argo CD installed successfully"
    print_status "Argo CD components:"
    kubectl get pods -n argocd
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          Setup Completed Successfully!                     ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    print_status "Cluster Name: iot-cluster"
    print_status "Cluster Status:"
    kubectl get nodes
    echo ""
    print_status "Namespaces:"
    kubectl get namespaces
    echo ""
    print_status "Argo CD Status:"
    kubectl get pods -n argocd
    echo ""
    print_status "Your K3d cluster with Argo CD is ready!"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Create your configuration files (deployment.yaml, argocd-application.yaml) in ../confs/"
    echo "2. Create a GitHub repository with your k8s manifests"
    echo "3. Update argocd-application.yaml with your GitHub repository URL"
    echo "4. Apply the configurations: kubectl apply -f ../confs/argocd-application.yaml"
    echo ""
    echo -e "${YELLOW}Useful commands:${NC}"
    echo "kubectl get ns                          # List namespaces"
    echo "kubectl get pods -n argocd              # Check Argo CD pods"
    echo "kubectl get pods -n dev                 # Check deployed applications"
    echo "kubectl get applications -n argocd      # Check Argo CD applications"
    echo ""
}

# Main execution
main() {
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║      K3d Installation and Argo CD Setup                   ║"
    echo "║              Part 3: Inception of Things                  ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    
    print_status "Starting installation and setup..."
    echo ""
    
    print_status "=== Phase 1: System Update ==="
    update_system
    echo ""
    
    print_status "=== Phase 2: Installing Dependencies ==="
    install_docker
    install_kubectl
    install_k3d
    install_git
    install_curl
    echo ""
    
    print_status "=== Phase 3: Creating K3d Cluster ==="
    create_k3d_cluster
    echo ""
    
    print_status "=== Phase 4: Creating Namespaces ==="
    create_namespaces
    echo ""
    
    print_status "=== Phase 5: Installing Argo CD ==="
    install_argocd
    echo ""
    
    print_summary
}

# Run main function
main
