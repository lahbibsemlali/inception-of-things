#!/bin/bash
set -euo pipefail

NAMESPACE="gitlab"
DOMAIN="k3d.gitlab.com"
GITLAB_HOST="gitlab.${DOMAIN}"

echo "Installing GitLab on k3d..."

# Check prerequisites
command -v kubectl &>/dev/null || { echo "kubectl not found"; exit 1; }
command -v helm &>/dev/null || sudo snap install helm --classic

# Create namespace
kubectl create namespace "$NAMESPACE" 2>/dev/null || true

# Configure hosts
grep -q "127.0.0.1 ${GITLAB_HOST}" /etc/hosts || \
    echo "127.0.0.1 ${GITLAB_HOST}" | sudo tee -a /etc/hosts

# Deploy GitLab
helm repo add gitlab https://charts.gitlab.io/ 2>/dev/null || true
helm repo update

helm upgrade --install gitlab gitlab/gitlab \
    --namespace "$NAMESPACE" \
    --values https://gitlab.com/gitlab-org/charts/gitlab/raw/master/examples/values-minikube-minimum.yaml \
    --set global.hosts.domain="$DOMAIN" \
    --set global.hosts.externalIP=0.0.0.0 \
    --set global.hosts.https=false \
    --set certmanager.install=false \
    --set global.ingress.configureCertmanager=false \
    --timeout 600s \
    --wait

# Wait for pods
kubectl wait --for=condition=ready --timeout=1200s pod -l app=webservice -n "$NAMESPACE"

# Get password
PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n "$NAMESPACE" -o jsonpath="{.data.password}" | base64 -d)

# Setup port forward
pkill -f "kubectl port-forward.*gitlab-webservice" 2>/dev/null || true
kubectl port-forward svc/gitlab-webservice-default -n "$NAMESPACE" 8181:8181 &

echo ""
echo "✓ GitLab deployed successfully!"
echo "  URL:      http://${GITLAB_HOST}:8181"
echo "  Username: root"
echo "  Password: ${PASSWORD}"