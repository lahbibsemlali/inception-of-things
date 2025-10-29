#!/bin/bash
set -euo pipefail

# ============================================================================
# GitLab on k3d Deployment Script
# ============================================================================
# This script automates the deployment of GitLab on a k3d cluster
# with proper error handling, logging, and resource verification.
# ============================================================================

# Define colors for output
readonly GREEN="\033[32m"
readonly RED="\033[31m"
readonly YELLOW="\033[33m"
readonly BLUE="\033[34m"
readonly RESET="\033[0m"

# Configuration variables
readonly NAMESPACE="gitlab"
readonly DOMAIN="k3d.gitlab.com"
readonly GITLAB_HOST="gitlab.${DOMAIN}"
readonly HELM_TIMEOUT="600s"
readonly POD_WAIT_TIMEOUT="1200s"
readonly PORT_FORWARD_PORT="8181"

# Log file for debugging
readonly LOG_FILE="/tmp/gitlab-deploy-$(date +%Y%m%d-%H%M%S).log"

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    local level=$1
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${msg}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}ℹ${RESET} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓${RESET} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗${RESET} $*" | tee -a "$LOG_FILE" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠${RESET} $*" | tee -a "$LOG_FILE"
}

exit_error() {
    log_error "$1"
    log_error "Check log file: $LOG_FILE"
    exit 1
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        exit_error "Required command not found: $1"
    fi
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

preflight_checks() {
    log_info "Running pre-flight checks..."
    
    # Check required commands
    check_command kubectl
    check_command sudo
    check_command snap
    check_command grep
    check_command base64
    
    # Check kubectl connectivity
    if ! kubectl cluster-info &>/dev/null; then
        exit_error "Cannot connect to Kubernetes cluster. Is k3d running?"
    fi
    
    # Check available resources
    local nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    if [ "$nodes" -eq 0 ]; then
        exit_error "No Kubernetes nodes found"
    fi
    
    log_success "Pre-flight checks passed"
}

# ============================================================================
# Namespace Management
# ============================================================================

create_namespace() {
    log_info "Creating namespace: $NAMESPACE"
    
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_warning "Namespace $NAMESPACE already exists, skipping creation"
    else
        kubectl create namespace "$NAMESPACE" 2>&1 | tee -a "$LOG_FILE" || \
            exit_error "Failed to create namespace"
        log_success "Namespace created: $NAMESPACE"
    fi
}

# ============================================================================
# Helm Installation
# ============================================================================

install_helm() {
    log_info "Checking Helm installation..."
    
    if command -v helm &>/dev/null; then
        local helm_version=$(helm version --short 2>/dev/null)
        log_success "Helm already installed: $helm_version"
    else
        log_info "Installing Helm via snap..."
        sudo snap install helm --classic 2>&1 | tee -a "$LOG_FILE" || \
            exit_error "Failed to install Helm"
        log_success "Helm installed successfully"
    fi
}

# ============================================================================
# /etc/hosts Configuration
# ============================================================================

configure_hosts() {
    log_info "Configuring /etc/hosts..."
    
    local host_entry="127.0.0.1 ${GITLAB_HOST}"
    
    if grep -q "$host_entry" /etc/hosts 2>/dev/null; then
        log_warning "/etc/hosts entry already exists"
    else
        echo "$host_entry" | sudo tee -a /etc/hosts > /dev/null || \
            exit_error "Failed to update /etc/hosts"
        log_success "Added entry to /etc/hosts: $host_entry"
    fi
}

# ============================================================================
# GitLab Deployment
# ============================================================================

deploy_gitlab() {
    log_info "Deploying GitLab via Helm..."
    
    # Add and update Helm repository
    helm repo add gitlab https://charts.gitlab.io/ 2>&1 | tee -a "$LOG_FILE" || \
        log_warning "GitLab repo might already exist"
    
    helm repo update 2>&1 | tee -a "$LOG_FILE" || \
        exit_error "Failed to update Helm repositories"
    
    log_success "Helm repositories updated"
    
    # Deploy GitLab
    log_info "Installing GitLab chart (this may take several minutes)..."
    
    helm upgrade --install gitlab gitlab/gitlab \
        --namespace "$NAMESPACE" \
        --create-namespace \
        --values https://gitlab.com/gitlab-org/charts/gitlab/raw/master/examples/values-minikube-minimum.yaml \
        --set global.hosts.domain="$DOMAIN" \
        --set global.hosts.externalIP=0.0.0.0 \
        --set global.hosts.https=false \
        --set certmanager.install=false \
        --set global.ingress.configureCertmanager=false \
        --timeout "$HELM_TIMEOUT" \
        --wait 2>&1 | tee -a "$LOG_FILE" || \
        exit_error "GitLab Helm installation failed"
    
    log_success "GitLab Helm chart deployed"
}

# ============================================================================
# Wait for GitLab Readiness
# ============================================================================

wait_for_gitlab() {
    log_info "Waiting for GitLab pods to be ready (timeout: ${POD_WAIT_TIMEOUT})..."
    
    if kubectl wait --for=condition=ready \
        --timeout="$POD_WAIT_TIMEOUT" \
        pod -l app=webservice \
        -n "$NAMESPACE" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "GitLab pods are ready"
    else
        log_error "GitLab pods failed to become ready"
        log_info "Checking pod status..."
        kubectl get pods -n "$NAMESPACE" 2>&1 | tee -a "$LOG_FILE"
        exit_error "GitLab deployment verification failed"
    fi
}

# ============================================================================
# Password Retrieval
# ============================================================================

get_gitlab_password() {
    log_info "Retrieving GitLab root password..."
    
    local password
    password=$(kubectl get secret gitlab-gitlab-initial-root-password \
        -n "$NAMESPACE" \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 --decode)
    
    if [ -z "$password" ]; then
        log_warning "Could not retrieve password from secret"
        return 1
    fi
    
    echo -e "\n${GREEN}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}  GitLab Deployment Successful!${RESET}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${BLUE}  URL:${RESET}      http://${GITLAB_HOST}:${PORT_FORWARD_PORT}"
    echo -e "${BLUE}  Username:${RESET} root"
    echo -e "${BLUE}  Password:${RESET} ${password}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${RESET}\n"
}

# ============================================================================
# Port Forwarding
# ============================================================================

setup_port_forward() {
    log_info "Setting up port forwarding..."
    
    # Kill any existing port-forward processes
    pkill -f "kubectl port-forward.*gitlab-webservice" 2>/dev/null || true
    
    # Start port forwarding in background
    kubectl port-forward svc/gitlab-webservice-default \
        -n "$NAMESPACE" \
        "${PORT_FORWARD_PORT}:8181" \
        >> "$LOG_FILE" 2>&1 &
    
    local pf_pid=$!
    sleep 2
    
    if ps -p $pf_pid > /dev/null; then
        log_success "Port forwarding active (PID: $pf_pid)"
        log_info "Access GitLab at: http://${GITLAB_HOST}:${PORT_FORWARD_PORT}"
    else
        log_warning "Port forwarding may have failed. Check logs."
    fi
}

# ============================================================================
# Cleanup Function
# ============================================================================

cleanup() {
    log_info "Cleaning up temporary resources..."
    # Add any cleanup tasks here if needed
}

trap cleanup EXIT

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo -e "${BLUE}"
    echo "═══════════════════════════════════════════════════════════"
    echo "  GitLab on k3d - Automated Deployment Script"
    echo "═══════════════════════════════════════════════════════════"
    echo -e "${RESET}"
    echo "Log file: $LOG_FILE"
    echo ""
    
    preflight_checks
    create_namespace
    install_helm
    configure_hosts
    deploy_gitlab
    wait_for_gitlab
    get_gitlab_password
    setup_port_forward
    
    echo ""
    log_success "Deployment complete!"
    log_info "To stop port forwarding: pkill -f 'kubectl port-forward.*gitlab-webservice'"
    log_info "To uninstall GitLab: helm uninstall gitlab -n $NAMESPACE"
}

main "$@"
