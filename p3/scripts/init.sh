#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Installing Required Tools ===${NC}\n"

# Update system
echo -e "${GREEN}[1/6]${NC} Updating system..."
sudo apt-get update -qq && sudo apt-get upgrade -y -qq

# Install Docker
if ! command -v docker &> /dev/null; then
    echo -e "${GREEN}[2/6]${NC} Installing Docker..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker $USER
else
    echo -e "${GREEN}[2/6]${NC} Docker already installed"
fi

# Install kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${GREEN}[3/6]${NC} Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install kubectl /usr/local/bin/kubectl && rm kubectl
else
    echo -e "${GREEN}[3/6]${NC} kubectl already installed"
fi

# Install k3d
if ! command -v k3d &> /dev/null; then
    echo -e "${GREEN}[4/6]${NC} Installing k3d..."
    wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
else
    echo -e "${GREEN}[4/6]${NC} k3d already installed"
fi

# Install git
if ! command -v git &> /dev/null; then
    echo -e "${GREEN}[5/6]${NC} Installing git..."
    sudo apt-get install -y git -qq
else
    echo -e "${GREEN}[5/6]${NC} git already installed"
fi

# Install curl/wget
echo -e "${GREEN}[6/6]${NC} Installing curl and wget..."
sudo apt-get install -y curl wget -qq

echo -e "\n${GREEN}✓ Installation complete!${NC}"