#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CLUSTER_NAME="iot-cluster"
ARGOCD_APP_FILE="../confs/argocd-application.yaml"

echo -e "${GREEN}=== Setting up K3d Cluster with ArgoCD ===${NC}\n"

# Check if necessary apps are installed
for cmd in docker kubectl k3d; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: $cmd not installed. Run ./init.sh first${NC}"
        exit 1
    fi
done

# Create cluster
echo -e "${GREEN}[1/6]${NC} Creating cluster: $CLUSTER_NAME"
k3d cluster create $CLUSTER_NAME

# Wait for nodes
echo -e "${GREEN}[2/6]${NC} Waiting for nodes..."
kubectl wait --for=condition=ready nodes --all --timeout=300s

# Create namespaces
echo -e "${GREEN}[3/6]${NC} Creating namespaces..."
kubectl create namespace argocd
kubectl create namespace dev

# Install ArgoCD
echo -e "${GREEN}[4/6]${NC} Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD
echo -e "${GREEN}[5/6]${NC} Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd 2>/dev/null || sleep 30

# Apply ArgoCD application config
echo -e "${GREEN}[6/6]${NC} Applying ArgoCD application..."
if [ -f "$ARGOCD_APP_FILE" ]; then
    kubectl apply -f "$ARGOCD_APP_FILE"
    echo -e "${GREEN}✓ ArgoCD application applied${NC}"
else
    echo -e "${YELLOW}⚠ File not found: $ARGOCD_APP_FILE${NC}"
fi

echo -e "\n${GREEN}✓ Setup complete!${NC}\n"

echo -e "${GREEN}Cluster nodes:${NC}"
kubectl get nodes
echo ""

echo -e "${GREEN}ArgoCD pods:${NC}"
kubectl get pods -n argocd
echo ""

if [ -f "$ARGOCD_APP_FILE" ]; then
    echo -e "${GREEN}ArgoCD applications:${NC}"
    kubectl get applications -n argocd
    echo ""
fi

echo -e "\n${YELLOW}To access ArgoCD:${NC}"
echo "  1. Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
echo "  2. Port-forward: kubectl port-forward svc/argocd-server -n argocd 8081:443"
echo "  3. Open: http://localhost:8081"
echo "  4. Login: admin / <password>"