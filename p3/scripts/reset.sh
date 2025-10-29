#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Confirmation
confirm() {
    local prompt="$1"
    local response
    
    read -p "$(echo -e ${YELLOW}$prompt${NC})" response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Kill all kubectl processes
kill_kubectl_processes() {
    print_status "Killing all kubectl port-forward processes..."
    pkill -f "kubectl port-forward" 2>/dev/null || print_warning "No kubectl port-forward processes running"
    
    print_status "Killing all kubectl proxy processes..."
    pkill -f "kubectl proxy" 2>/dev/null || print_warning "No kubectl proxy processes running"
}

# Delete all K3d clusters
delete_all_k3d_clusters() {
    print_status "Listing all K3d clusters..."
    k3d cluster list
    
    print_status "Deleting all K3d clusters..."
    CLUSTERS=$(k3d cluster list -o json 2>/dev/null | grep -o '"name":"[^"]*"' | cut -d'"' -f4 || echo "")
    
    if [ -z "$CLUSTERS" ]; then
        print_warning "No K3d clusters found"
    else
        for cluster in $CLUSTERS; do
            print_status "Deleting cluster: $cluster"
            k3d cluster delete "$cluster" 2>/dev/null || print_warning "Failed to delete $cluster"
        done
    fi
    
    sleep 3
}

# Clean all Docker containers related to K3d
clean_k3d_containers() {
    print_status "Stopping and removing all K3d containers..."
    
    # Stop all k3d containers
    docker ps -a | grep k3d | awk '{print $1}' | xargs -r docker stop 2>/dev/null || print_warning "No K3d containers to stop"
    
    # Remove all k3d containers
    docker ps -a | grep k3d | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null || print_warning "No K3d containers to remove"
}

# Clean all Docker images related to K3d
clean_k3d_images() {
    print_status "Removing K3d Docker images..."
    
    # Remove k3d images
    docker images | grep k3d | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || print_warning "No K3d images to remove"
    
    # Remove k3s images
    docker images | grep k3s | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || print_warning "No K3s images to remove"
}

# Clean Docker networks
clean_docker_networks() {
    print_status "Removing K3d Docker networks..."
    
    docker network ls | grep k3d | awk '{print $1}' | xargs -r docker network rm 2>/dev/null || print_warning "No K3d networks to remove"
}

# Clean Docker volumes
clean_docker_volumes() {
    print_status "Removing K3d Docker volumes..."
    
    docker volume ls | grep k3d | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || print_warning "No K3d volumes to remove"
}

# Clean kubeconfig
clean_kubeconfig() {
    print_status "Cleaning kubeconfig..."
    
    # Remove all k3d contexts
    CONTEXTS=$(kubectl config get-contexts -o name 2>/dev/null | grep k3d || echo "")
    
    if [ -z "$CONTEXTS" ]; then
        print_warning "No K3d contexts found in kubeconfig"
    else
        for context in $CONTEXTS; do
            print_status "Deleting context: $context"
            kubectl config delete-context "$context" 2>/dev/null || print_warning "Failed to delete context $context"
        done
    fi
    
    # Remove all k3d clusters from kubeconfig
    CLUSTERS=$(kubectl config get-clusters 2>/dev/null | grep k3d || echo "")
    
    if [ ! -z "$CLUSTERS" ]; then
        for cluster in $CLUSTERS; do
            print_status "Deleting cluster config: $cluster"
            kubectl config delete-cluster "$cluster" 2>/dev/null || print_warning "Failed to delete cluster $cluster"
        done
    fi
    
    # Remove all k3d users from kubeconfig
    USERS=$(kubectl config view -o jsonpath='{.users[*].name}' 2>/dev/null | tr ' ' '\n' | grep k3d || echo "")
    
    if [ ! -z "$USERS" ]; then
        for user in $USERS; do
            print_status "Deleting user: $user"
            kubectl config delete-user "$user" 2>/dev/null || print_warning "Failed to delete user $user"
        done
    fi
}


# Clean temporary files
clean_temp_files() {
    print_status "Cleaning temporary files..."
    
    rm -f /tmp/deployment.yaml 2>/dev/null || true
    rm -f /tmp/argocd-app.yaml 2>/dev/null || true
    rm -f /tmp/gitlab-root-password.txt 2>/dev/null || true
    
    print_status "Temporary files cleaned"
}

# Prune Docker system
prune_docker() {
    print_status "Pruning Docker system..."
    
    docker system prune -af --volumes 2>/dev/null || print_warning "Docker prune failed"
}

# Verify cleanup
verify_cleanup() {
    echo ""
    print_status "Verifying cleanup..."
    echo ""
    
    print_info "K3d clusters:"
    k3d cluster list || print_warning "K3d not available"
    
    echo ""
    print_info "Docker containers (k3d related):"
    docker ps -a | grep k3d || print_status "No K3d containers found ✓"
    
    echo ""
    print_info "Docker images (k3d/k3s related):"
    docker images | grep -E "k3d|k3s" || print_status "No K3d/K3s images found ✓"
    
    echo ""
    print_info "Docker networks (k3d related):"
    docker network ls | grep k3d || print_status "No K3d networks found ✓"
    
    echo ""
    print_info "Docker volumes (k3d related):"
    docker volume ls | grep k3d || print_status "No K3d volumes found ✓"
    
    echo ""
    print_info "Kubectl contexts (k3d related):"
    kubectl config get-contexts | grep k3d || print_status "No K3d contexts found ✓"
    
    echo ""
    print_info "Port-forward processes:"
    ps aux | grep "kubectl port-forward" | grep -v grep || print_status "No port-forward processes found ✓"
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          Complete Reset Finished Successfully!             ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    print_status "All K3d clusters, containers, images, networks, and volumes removed"
    print_status "Kubeconfig cleaned"
    print_status "Temporary files removed"
    print_status "System is completely clean"
    echo ""
    print_info "You can now run setup.sh again to start fresh"
    echo ""
}

# Main execution
main() {
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          Complete System Reset Script                     ║"
    echo "║              Inception of Things                          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    
    print_warning "This script will:"
    echo "  1. Kill all kubectl processes"
    echo "  2. Delete ALL K3d clusters"
    echo "  3. Remove all K3d containers"
    echo "  4. Remove all K3d images"
    echo "  5. Remove all K3d networks"
    echo "  6. Remove all K3d volumes"
    echo "  7. Clean kubeconfig"
    echo "  8. Uninstall all Helm releases"
    echo "  9. Remove temporary files"
    echo "  10. Prune Docker system"
    echo ""
    
    if ! confirm "Are you ABSOLUTELY SURE you want to proceed? (yes/no): "; then
        print_error "Reset cancelled"
        exit 1
    fi
    
    echo ""
    print_status "Starting complete system reset..."
    echo ""
    
    # Phase 1: Stop processes
    print_status "=== Phase 1: Stopping Processes ==="
    kill_kubectl_processes
    echo ""
    
    # Phase 4: Delete clusters
    print_status "=== Phase 3: Deleting K3d Clusters ==="
    delete_all_k3d_clusters
    echo ""
    
    # Phase 5: Clean containers
    print_status "=== Phase 4: Cleaning Docker Containers ==="
    clean_k3d_containers
    echo ""
    
    # Phase 6: Clean networks
    print_status "=== Phase 5: Cleaning Docker Networks ==="
    clean_docker_networks
    echo ""
    
    # Phase 7: Clean volumes
    print_status "=== Phase 6: Cleaning Docker Volumes ==="
    clean_docker_volumes
    echo ""
    
    # Phase 8: Clean images
    print_status "=== Phase 7: Cleaning Docker Images ==="
    clean_k3d_images
    echo ""
    
    # Phase 9: Clean kubeconfig
    print_status "=== Phase 8: Cleaning Kubeconfig ==="
    clean_kubeconfig
    echo ""
    
    # Phase 10: Clean temp files
    print_status "=== Phase 9: Cleaning Temporary Files ==="
    clean_temp_files
    echo ""
    
    # Phase 11: Docker prune
    print_status "=== Phase 10: Pruning Docker System ==="
    prune_docker
    echo ""
    
    # Verify cleanup
    verify_cleanup
    
    # Print summary
    print_summary
}

# Run main function
main
