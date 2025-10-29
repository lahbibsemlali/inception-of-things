#!/bin/bash
set -euo pipefail

# Configuration
readonly NAMESPACE="gitlab"
readonly DOMAIN="k3d.gitlab.com"
readonly GITLAB_HOST="gitlab.${DOMAIN}"
readonly PORT_FORWARD_PORT="8181"

# Colors
readonly GREEN="\033[32m"
readonly RED="\033[31m"
readonly YELLOW="\033[33m"
readonly BLUE="\033[34m"
readonly CYAN="\033[36m"
readonly RESET="\033[0m"

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}ℹ${RESET} $*"
}

log_success() {
    echo -e "${GREEN}✓${RESET} $*"
}

log_error() {
    echo -e "${RED}✗${RESET} $*" >&2
}

# ============================================================================
# Feature Functions
# ============================================================================

show_logs() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}  GitLab Logs${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${RESET}\n"
    
    log_info "Fetching logs from GitLab webservice pods..."
    
    if kubectl logs -n "$NAMESPACE" -l app=webservice --tail=100 --prefix 2>/dev/null; then
        log_success "Logs retrieved successfully"
    else
        log_error "Failed to retrieve logs"
        log_info "Checking pod status..."
        kubectl get pods -n "$NAMESPACE" -l app=webservice
    fi
}

show_password() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}  GitLab Credentials${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${RESET}\n"
    
    local password
    password=$(kubectl get secret gitlab-gitlab-initial-root-password \
        -n "$NAMESPACE" \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 --decode)
    
    if [ -z "$password" ]; then
        log_error "Could not retrieve password from secret"
        log_info "Check if GitLab is properly deployed"
        return 1
    fi
    
    echo -e "${GREEN}  URL:${RESET}      http://${GITLAB_HOST}:${PORT_FORWARD_PORT}"
    echo -e "${GREEN}  Username:${RESET} root"
    echo -e "${GREEN}  Password:${RESET} ${password}"
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${RESET}\n"
}

run_port_forward() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}  Port Forwarding${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${RESET}\n"
    
    log_info "Checking for existing port-forward processes..."
    
    # Kill any existing port-forward processes
    if pkill -f "kubectl port-forward.*gitlab-webservice" 2>/dev/null; then
        log_success "Killed existing port-forward process"
        sleep 1
    else
        log_info "No existing port-forward found"
    fi
    
    # Check if service exists
    if ! kubectl get svc gitlab-webservice-default -n "$NAMESPACE" &>/dev/null; then
        log_error "Service gitlab-webservice-default not found in namespace $NAMESPACE"
        return 1
    fi
    
    log_info "Starting port forwarding..."
    
    # Start port forwarding in background
    kubectl port-forward svc/gitlab-webservice-default \
        -n "$NAMESPACE" \
        "${PORT_FORWARD_PORT}:8181" \
        > /tmp/gitlab-portforward.log 2>&1 &
    
    local pf_pid=$!
    sleep 2
    
    if ps -p $pf_pid > /dev/null 2>&1; then
        log_success "Port forwarding active (PID: $pf_pid)"
        log_info "Access GitLab at: http://${GITLAB_HOST}:${PORT_FORWARD_PORT}"
        echo -e "\n${YELLOW}⚠${RESET}  To stop: pkill -f 'kubectl port-forward.*gitlab-webservice'"
        echo -e "${YELLOW}⚠${RESET}  Logs at: /tmp/gitlab-portforward.log\n"
    else
        log_error "Port forwarding failed to start"
        log_info "Check logs at: /tmp/gitlab-portforward.log"
        if [ -f /tmp/gitlab-portforward.log ]; then
            echo -e "\n${RED}Error details:${RESET}"
            cat /tmp/gitlab-portforward.log
        fi
        return 1
    fi
}

# ============================================================================
# Menu System
# ============================================================================

show_menu() {
    echo -e "\n${BLUE}╔═══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║${RESET}           ${CYAN}GitLab Management Menu${RESET}                      ${BLUE}║${RESET}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${RESET}\n"
    echo -e "  ${GREEN}1)${RESET} Show GitLab logs"
    echo -e "  ${GREEN}2)${RESET} Show password and credentials"
    echo -e "  ${GREEN}3)${RESET} Start/restart port forwarding"
    echo -e "  ${GREEN}4)${RESET} Show all (logs, password, port-forward)"
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
            show_logs
            show_password
            run_port_forward
            ;;
        0)
            echo -e "\n${GREEN}Goodbye!${RESET}\n"
            exit 0
            ;;
        *)
            log_error "Invalid choice. Please select 0-4."
            ;;
    esac
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    # Check if kubectl is available
    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl not found. Please install kubectl first."
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Is k3d running?"
        exit 1
    fi
    
    # If argument provided, execute directly
    if [ $# -gt 0 ]; then
        handle_choice "$1"
        exit $?
    fi
    
    # Interactive mode
    while true; do
        show_menu
        echo -ne "${CYAN}Enter your choice [0-4]:${RESET} "
        read -r choice
        handle_choice "$choice"
        
        echo -ne "\n${YELLOW}Press Enter to continue...${RESET}"
        read -r
    done
}

main "$@"
