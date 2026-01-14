#!/bin/bash
# =============================================================================
# MoveX Server Setup Script
# Installs all required dependencies on Ubuntu server
# Run as root: sudo ./01-setup-server.sh
# =============================================================================

set -euo pipefail

# Load environment utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/env-loader.sh"

require_root

log_info "=========================================="
log_info "  MoveX Server Setup Script"
log_info "  Target: Ubuntu Server"
log_info "=========================================="

# -----------------------------------------------------------------------------
# Update System Packages
# -----------------------------------------------------------------------------
log_info "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# -----------------------------------------------------------------------------
# Install Essential Tools
# -----------------------------------------------------------------------------
log_info "Installing essential tools..."
apt-get install -y \
    curl \
    wget \
    git \
    unzip \
    zip \
    htop \
    vim \
    jq \
    netcat-openbsd \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common

# -----------------------------------------------------------------------------
# Install Docker
# -----------------------------------------------------------------------------
if command_exists docker; then
    log_info "Docker is already installed"
    docker --version
else
    log_info "Installing Docker..."
    
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up the repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    log_success "Docker installed successfully"
    docker --version
fi

# -----------------------------------------------------------------------------
# Install Nginx
# -----------------------------------------------------------------------------
if command_exists nginx; then
    log_info "Nginx is already installed"
    nginx -v
else
    log_info "Installing Nginx..."
    apt-get install -y nginx
    
    # Start and enable Nginx
    systemctl start nginx
    systemctl enable nginx
    
    log_success "Nginx installed successfully"
    nginx -v
fi

# -----------------------------------------------------------------------------
# Install OpenJDK 23
# -----------------------------------------------------------------------------
if command_exists java; then
    JAVA_VERSION=$(java -version 2>&1 | head -1 | cut -d'"' -f2)
    log_info "Java is already installed: $JAVA_VERSION"
else
    log_info "Installing OpenJDK 23..."
    
    # Download and install OpenJDK 23
    JAVA_URL="https://download.java.net/java/GA/jdk23/3c5b90190c68498b986a97f276efd28a/37/GPL/openjdk-23_linux-x64_bin.tar.gz"
    JAVA_INSTALL_DIR="/opt/jdk-23"
    
    wget -q --show-progress -O /tmp/openjdk-23.tar.gz "$JAVA_URL"
    mkdir -p "$JAVA_INSTALL_DIR"
    tar -xzf /tmp/openjdk-23.tar.gz -C /opt/
    rm /tmp/openjdk-23.tar.gz
    
    # Set up alternatives
    update-alternatives --install /usr/bin/java java "${JAVA_INSTALL_DIR}/bin/java" 1
    update-alternatives --install /usr/bin/javac javac "${JAVA_INSTALL_DIR}/bin/javac" 1
    
    # Set JAVA_HOME
    echo "export JAVA_HOME=${JAVA_INSTALL_DIR}" >> /etc/profile.d/java.sh
    echo 'export PATH=$JAVA_HOME/bin:$PATH' >> /etc/profile.d/java.sh
    source /etc/profile.d/java.sh
    
    log_success "OpenJDK 23 installed successfully"
    java -version
fi

# -----------------------------------------------------------------------------
# Install Node.js 20 & Yarn
# -----------------------------------------------------------------------------
if command_exists node; then
    NODE_VERSION=$(node --version)
    log_info "Node.js is already installed: $NODE_VERSION"
else
    log_info "Installing Node.js 20..."
    
    # Install Node.js via NodeSource
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    
    log_success "Node.js installed successfully"
    node --version
fi

# Install Yarn
if command_exists yarn; then
    log_info "Yarn is already installed"
    yarn --version
else
    log_info "Installing Yarn..."
    npm install -g yarn
    log_success "Yarn installed successfully"
    yarn --version
fi

# -----------------------------------------------------------------------------
# Create Deployment Directories
# -----------------------------------------------------------------------------
log_info "Creating deployment directories..."

ensure_dir "/opt/movex"
ensure_dir "/opt/movex/src"
ensure_dir "/opt/movex/logs"
ensure_dir "/var/www/movex-fe"
ensure_dir "/var/log/movex"

# Set proper permissions
chown -R root:root /opt/movex
chown -R www-data:www-data /var/www/movex-fe
chmod -R 755 /var/www/movex-fe

# -----------------------------------------------------------------------------
# Configure System Limits
# -----------------------------------------------------------------------------
log_info "Configuring system limits..."

# Increase file descriptor limits for Docker
cat > /etc/security/limits.d/docker.conf << EOF
* soft nofile 65536
* hard nofile 65536
root soft nofile 65536
root hard nofile 65536
EOF

# Configure sysctl for Docker networking
cat > /etc/sysctl.d/99-docker.conf << EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
log_info ""
log_info "=========================================="
log_success "  Server Setup Complete!"
log_info "=========================================="
log_info ""
log_info "Installed components:"
log_info "  - Docker:   $(docker --version 2>/dev/null || echo 'N/A')"
log_info "  - Nginx:    $(nginx -v 2>&1 | cut -d'/' -f2)"
log_info "  - Java:     $(java -version 2>&1 | head -1)"
log_info "  - Node.js:  $(node --version 2>/dev/null || echo 'N/A')"
log_info "  - Yarn:     $(yarn --version 2>/dev/null || echo 'N/A')"
log_info ""
log_info "Created directories:"
log_info "  - /opt/movex          (deployment root)"
log_info "  - /opt/movex/src      (source code)"
log_info "  - /var/www/movex-fe   (frontend files)"
log_info "  - /var/log/movex      (application logs)"
log_info ""
log_info "Next step: Run ./02-clone-repos.sh"
