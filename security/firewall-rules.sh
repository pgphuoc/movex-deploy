#!/bin/bash
# =============================================================================
# MoveX Firewall Configuration Script
# Configures UFW firewall rules for secure deployment
# Run as root: sudo ./firewall-rules.sh
# =============================================================================

set -euo pipefail

# Load environment utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/utils/env-loader.sh"

require_root

log_info "=========================================="
log_info "  MoveX Firewall Configuration"
log_info "=========================================="

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
# External ports (allowed from anywhere)
NGINX_API_PORT="${NGINX_API_PORT:-8080}"
NGINX_FRONTEND_PORT="${NGINX_FRONTEND_PORT:-8084}"
SSH_PORT="${SSH_PORT:-2226}"

# Internal ports (blocked from external access)
INTERNAL_PORTS=(
    "8180"  # System service
    "8181"  # MasterData service
    "8182"  # OMS service
    "8183"  # TMS service
    "8185"  # Auth service
    "5435"  # PostgreSQL
    "6389"  # Redis
)

# -----------------------------------------------------------------------------
# Check if UFW is installed
# -----------------------------------------------------------------------------
if ! command_exists ufw; then
    log_info "Installing UFW..."
    apt-get update -y
    apt-get install -y ufw
fi

# -----------------------------------------------------------------------------
# Reset UFW to defaults
# -----------------------------------------------------------------------------
log_info "Resetting UFW to defaults..."
yes | ufw reset 2>/dev/null || true

# Set default policies
ufw default deny incoming
ufw default allow outgoing

log_success "Default policies set: deny incoming, allow outgoing"

# -----------------------------------------------------------------------------
# Allow Essential Ports
# -----------------------------------------------------------------------------
log_info ""
log_info "Configuring allowed ports..."

# SSH (critical - don't lock yourself out!)
log_info "  Allowing SSH on port ${SSH_PORT}..."
ufw allow ${SSH_PORT}/tcp comment 'SSH access'

# Nginx API Gateway
log_info "  Allowing API Gateway on port ${NGINX_API_PORT}..."
ufw allow ${NGINX_API_PORT}/tcp comment 'MoveX API Gateway'

# Nginx Frontend
log_info "  Allowing Frontend on port ${NGINX_FRONTEND_PORT}..."
ufw allow ${NGINX_FRONTEND_PORT}/tcp comment 'MoveX Frontend'

# HTTP/HTTPS (optional, uncomment if needed)
# log_info "  Allowing HTTP/HTTPS..."
# ufw allow 80/tcp comment 'HTTP'
# ufw allow 443/tcp comment 'HTTPS'

# -----------------------------------------------------------------------------
# Block Direct Access to Internal Ports
# -----------------------------------------------------------------------------
log_info ""
log_info "Blocking direct access to internal ports..."

for port in "${INTERNAL_PORTS[@]}"; do
    log_info "  Blocking external access to port ${port}..."
    # Only allow from localhost/Docker network
    ufw deny from any to any port ${port} comment "Block external access to internal port ${port}"
done

# Allow Docker internal communication (docker0 and docker bridge networks)
log_info ""
log_info "Allowing Docker internal communication..."
ufw allow in on docker0
ufw allow in from 172.16.0.0/12 comment 'Docker bridge networks'
ufw allow in from 10.0.0.0/8 comment 'Docker overlay networks'

# -----------------------------------------------------------------------------
# Rate Limiting
# -----------------------------------------------------------------------------
log_info ""
log_info "Configuring rate limiting..."

# Rate limit SSH to prevent brute force
ufw limit ${SSH_PORT}/tcp comment 'Rate limit SSH'

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log_info ""
log_info "Enabling UFW logging..."
ufw logging medium

# -----------------------------------------------------------------------------
# Enable UFW
# -----------------------------------------------------------------------------
log_info ""
log_info "Enabling UFW..."
echo "y" | ufw enable

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
log_info ""
log_info "=========================================="
log_success "  Firewall Configuration Complete!"
log_info "=========================================="
log_info ""
log_info "UFW Status:"
ufw status verbose
log_info ""
log_info "Allowed external access:"
log_info "  ✓ SSH:        ${SSH_PORT}/tcp"
log_info "  ✓ API:        ${NGINX_API_PORT}/tcp"
log_info "  ✓ Frontend:   ${NGINX_FRONTEND_PORT}/tcp"
log_info ""
log_info "Blocked external access:"
for port in "${INTERNAL_PORTS[@]}"; do
    log_info "  ✗ Internal:   ${port}/tcp"
done
log_info ""
log_warning "IMPORTANT: Verify you can still SSH to the server!"
log_warning "If locked out, use cloud provider console to disable UFW."
