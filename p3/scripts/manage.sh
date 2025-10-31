set -euo pipefail

readonly ARGOCD_NAMESPACE="argocd"
readonly PORT_FORWARD_PORT="8080"

readonly GREEN="\033[32m"
readonly RED="\033[31m"
readonly YELLOW="\033[33m"
readonly BLUE="\033[34m"
readonly CYAN="\033[36m"
readonly RESET="\033[0m"

log_info() {
    echo -e "${BLUE}ℹ${RESET} $*"
}

log_success() {
    echo -e "${GREEN}✓${RESET} $*"
}

log_error() {
    echo -e "${RED}✗${RESET} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠${RESET} $*"
}

show_logs() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}  ArgoCD Logs${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${RESET}\n"
    
    echo -e "${BLUE}Select component:${RESET}"
    echo "  1) Application Controller"
    echo "  2) API Server"
    echo "  3) Repo Server"
    echo "  4) Redis"
    echo "  5) All components"
    echo -ne "\n${CYAN}Choice [1-5]:${RESET} "
    read -r component
    
    case $component in
        1)
            log_info "Fetching application-controller logs..."
            kubectl logs -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/name=argocd-application-controller --tail=100
            ;;
        2)
            log_info "Fetching argocd-server logs..."
            kubectl logs -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/name=argocd-server --tail=100
            ;;
        3)
            log_info "Fetching repo-server logs..."
            kubectl logs -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/name=argocd-repo-server --tail=100
            ;;
        4)
            log_info "Fetching redis logs..."
            kubectl logs -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/name=argocd-redis --tail=100
            ;;
        5)
            log_info "Fetching all ArgoCD component logs..."
            for component in application-controller server repo-server redis; do
                echo -e "\n${YELLOW}=== argocd-$component ===${RESET}"
                kubectl logs -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/name=argocd-$component --tail=50 2>/dev/null || echo "No logs available"
            done
            ;;
        *)
            log_error "Invalid choice"
            ;;
    esac
}

show_password() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}  ArgoCD Credentials${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${RESET}\n"
    
    local password
    
    if kubectl get secret argocd-initial-admin-secret -n "$ARGOCD_NAMESPACE" &>/dev/null; then
        password=$(kubectl get secret argocd-initial-admin-secret \
            -n "$ARGOCD_NAMESPACE" \
            -o jsonpath="{.data.password}" 2>/dev/null | base64 --decode)
    else
        log_warning "Initial admin secret not found. Password may have been changed."
        echo -e "\n${YELLOW}To reset the password:${RESET}"
        echo "kubectl patch secret argocd-secret -n $ARGOCD_NAMESPACE -p '{\"data\": {\"admin.password\": null, \"admin.passwordMtime\": null}}'"
        return 1
    fi
    
    if [ -z "$password" ]; then
        log_error "Could not retrieve password"
        return 1
    fi
    
    echo -e "${GREEN}  URL:${RESET}      https://localhost:${PORT_FORWARD_PORT}"
    echo -e "${GREEN}  Username:${RESET} admin"
    echo -e "${GREEN}  Password:${RESET} ${password}"
    echo -e "\n${YELLOW}Note:${RESET} Use 'argocd account update-password' to change password"
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${RESET}\n"
}

run_port_forward() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}  Port Forwarding${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${RESET}\n"
    
    log_info "Checking for existing port-forward processes..."
    
    if pkill -f "kubectl port-forward.*argocd-server" 2>/dev/null; then
        log_success "Killed existing port-forward process"
        sleep 1
    else
        log_info "No existing port-forward found"
    fi
    
    if ! kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" &>/dev/null; then
        log_error "Service argocd-server not found in namespace $ARGOCD_NAMESPACE"
        return 1
    fi
    
    log_info "Starting port forwarding..."
    
    kubectl port-forward svc/argocd-server \
        -n "$ARGOCD_NAMESPACE" \
        "${PORT_FORWARD_PORT}:443" \
        > /tmp/argocd-portforward.log 2>&1 &
    
    local pf_pid=$!
    sleep 2
    
    if ps -p $pf_pid > /dev/null 2>&1; then
        log_success "Port forwarding active (PID: $pf_pid)"
        log_info "Access ArgoCD at: https://localhost:${PORT_FORWARD_PORT}"
        log_warning "Accept the self-signed certificate in your browser"
        echo -e "\n${YELLOW}⚠${RESET}  To stop: pkill -f 'kubectl port-forward.*argocd-server'"
        echo -e "${YELLOW}⚠${RESET}  Logs at: /tmp/argocd-portforward.log\n"
    else
        log_error "Port forwarding failed to start"
        log_info "Check logs at: /tmp/argocd-portforward.log"
        if [ -f /tmp/argocd-portforward.log ]; then
            echo -e "\n${RED}Error details:${RESET}"
            cat /tmp/argocd-portforward.log
        fi
        return 1
    fi
}

show_applications() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}  ArgoCD Applications${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${RESET}\n"
    
    if ! kubectl get applications -n "$ARGOCD_NAMESPACE" &>/dev/null; then
        log_warning "No applications found or CRD not installed"
        return 1
    fi
    
    kubectl get applications -n "$ARGOCD_NAMESPACE" -o wide
    
    echo -e "\n${BLUE}Select an application for details (or press Enter to skip):${RESET}"
    local apps=$(kubectl get applications -n "$ARGOCD_NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
    
    if [ -z "$apps" ]; then
        log_info "No applications deployed"
        return 0
    fi
    
    echo -e "${GREEN}Available apps:${RESET} $apps"
    echo -ne "${CYAN}App name:${RESET} "
    read -r app_name
    
    if [ -n "$app_name" ]; then
        echo -e "\n${YELLOW}=== Application Details ===${RESET}"
        kubectl get application "$app_name" -n "$ARGOCD_NAMESPACE" -o yaml
    fi
}

show_status() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}  ArgoCD Cluster Status${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${RESET}\n"
    
    log_info "Checking ArgoCD components..."
    
    echo -e "\n${YELLOW}=== Pods ===${RESET}"
    kubectl get pods -n "$ARGOCD_NAMESPACE"
    
    echo -e "\n${YELLOW}=== Services ===${RESET}"
    kubectl get svc -n "$ARGOCD_NAMESPACE"
    
    echo -e "\n${YELLOW}=== Applications ===${RESET}"
    if kubectl get applications -n "$ARGOCD_NAMESPACE" &>/dev/null; then
        kubectl get applications -n "$ARGOCD_NAMESPACE"
    else
        log_info "No applications found"
    fi
    
    echo -e "\n${YELLOW}=== Recent Events ===${RESET}"
    kubectl get events -n "$ARGOCD_NAMESPACE" --sort-by='.lastTimestamp' | tail -10
}

sync_application() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}  Sync Application${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${RESET}\n"
    
    local apps=$(kubectl get applications -n "$ARGOCD_NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [ -z "$apps" ]; then
        log_error "No applications found"
        return 1
    fi
    
    echo -e "${GREEN}Available applications:${RESET} $apps"
    echo -ne "${CYAN}Enter application name to sync:${RESET} "
    read -r app_name
    
    if [ -z "$app_name" ]; then
        log_error "No application name provided"
        return 1
    fi
    
    log_info "Triggering sync for application: $app_name"
    
    kubectl patch application "$app_name" \
        -n "$ARGOCD_NAMESPACE" \
        --type merge \
        -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}' 2>/dev/null || {
        log_warning "Direct patch failed. Trying annotation method..."
        kubectl annotate application "$app_name" \
            -n "$ARGOCD_NAMESPACE" \
            argocd.argoproj.io/refresh=normal --overwrite
    }
    
    log_success "Sync triggered. Checking status..."
    sleep 2
    kubectl get application "$app_name" -n "$ARGOCD_NAMESPACE"
}

install_argocd_cli() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}  Install ArgoCD CLI${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${RESET}\n"
    
    if command -v argocd &>/dev/null; then
        local version=$(argocd version --client --short 2>/dev/null)
        log_success "ArgoCD CLI already installed: $version"
        return 0
    fi
    
    log_info "Installing ArgoCD CLI..."
    
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)
    
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_error "Unsupported architecture: $arch"; return 1 ;;
    esac
    
    local url="https://github.com/argoproj/argo-cd/releases/latest/download/argocd-${os}-${arch}"
    
    log_info "Downloading from: $url"
    
    if curl -sSL -o /tmp/argocd "$url"; then
        sudo install -m 755 /tmp/argocd /usr/local/bin/argocd
        rm /tmp/argocd
        log_success "ArgoCD CLI installed successfully"
        argocd version --client
    else
        log_error "Failed to download ArgoCD CLI"
        return 1
    fi
}

show_menu() {
    echo -e "\n${BLUE}╔═══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║${RESET}           ${CYAN}ArgoCD Management Menu${RESET}                      ${BLUE}║${RESET}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${RESET}\n"
    echo -e "  ${GREEN}1)${RESET} Show ArgoCD logs"
    echo -e "  ${GREEN}2)${RESET} Show password and credentials"
    echo -e "  ${GREEN}3)${RESET} Start/restart port forwarding"
    echo -e "  ${GREEN}4)${RESET} List applications"
    echo -e "  ${GREEN}5)${RESET} Show cluster status"
    echo -e "  ${GREEN}6)${RESET} Sync application"
    echo -e "  ${GREEN}7)${RESET} Install ArgoCD CLI"
    echo -e "  ${GREEN}8)${RESET} Show all (password + port-forward + status)"
    echo -e "  ${RED}0)${RESET} Exit"
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${RESET}"
}

handle_choice() {
    local choice=$1
    
    case $choice in
        1)
            show_logs
            ;;
        2)
            show_password
            ;;
        3)
            run_port_forward
            ;;
        4)
            show_applications
            ;;
        5)
            show_status
            ;;
        6)
            sync_application
            ;;
        7)
            install_argocd_cli
            ;;
        8)
            show_password
            run_port_forward
            show_status
            ;;
        0)
            echo -e "\n${GREEN}Goodbye!${RESET}\n"
            exit 0
            ;;
        *)
            log_error "Invalid choice. Please select 0-8."
            ;;
    esac
}

main() {
    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl not found. Please install kubectl first."
        exit 1
    fi
    
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Is k3d running?"
        exit 1
    fi
    
    if ! kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
        log_error "ArgoCD namespace not found. Is ArgoCD installed?"
        log_info "To install ArgoCD: kubectl create namespace argocd && kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
        exit 1
    fi
    
    if [ $# -gt 0 ]; then
        handle_choice "$1"
        exit $?
    fi
    
    while true; do
        show_menu
        echo -ne "${CYAN}Enter your choice [0-8]:${RESET} "
        read -r choice
        handle_choice "$choice"
        
        echo -ne "\n${YELLOW}Press Enter to continue...${RESET}"
        read -r
    done
}

main "$@"
