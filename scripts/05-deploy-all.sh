#!/bin/bash
# =============================================================================
# MoveX Full Deployment Script
# Runs all deployment steps in sequence
# Run as root: sudo ./05-deploy-all.sh
# =============================================================================

set -euo pipefail

# Load environment utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/env-loader.sh"

require_root

log_info "=========================================="
log_info "  MoveX Full Deployment Script"
log_info "=========================================="
log_info "  This script will:"
log_info "    1. Clone/update all repositories"
log_info "    2. Start infrastructure (DB, Redis)"
log_info "    3. Build all backend services"
log_info "    4. Build and deploy frontend"
log_info "    5. Start all services"
log_info "    6. Configure Nginx"
log_info "    7. Configure firewall"
log_info "=========================================="

# Load environment variables
load_env

# Validate critical environment variables
validate_env GITHUB_TOKEN GITHUB_BRANCH

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/docker/docker-compose.prod.yml"

# -----------------------------------------------------------------------------
# Step 1: Clone Repositories
# -----------------------------------------------------------------------------

log_info ""
log_info "=========================================="
log_info "  Step 1: Clone/Update Repositories"
log_info "=========================================="

bash "${SCRIPT_DIR}/02-clone-repos.sh"

# -----------------------------------------------------------------------------
# Step 2: Start Infrastructure
# -----------------------------------------------------------------------------

log_info ""
log_info "=========================================="
log_info "  Step 2: Start Infrastructure"
log_info "=========================================="

cd "${PROJECT_ROOT}/docker"

log_info "Starting PostgreSQL and Redis..."
docker compose -f docker-compose.prod.yml up -d db redis

# Wait for database to be healthy
log_info "Waiting for database to be ready..."
sleep 5

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5435}"

if wait_for_service "${DB_HOST}" "${DB_PORT}" "PostgreSQL" 60; then
    log_success "Database is ready"
else
    log_error "Database failed to start. Check logs:"
    log_error "  docker compose -f docker-compose.prod.yml logs db"
    exit 1
fi

REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6389}"

if wait_for_service "${REDIS_HOST}" "${REDIS_PORT}" "Redis" 30; then
    log_success "Redis is ready"
else
    log_error "Redis failed to start"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 3: Build Backend Services
# -----------------------------------------------------------------------------

log_info ""
log_info "=========================================="
log_info "  Step 3: Build Backend Services"
log_info "=========================================="

bash "${SCRIPT_DIR}/03-build-services.sh"

# -----------------------------------------------------------------------------
# Step 4: Build Frontend
# -----------------------------------------------------------------------------

log_info ""
log_info "=========================================="
log_info "  Step 4: Build Frontend"
log_info "=========================================="

bash "${SCRIPT_DIR}/04-build-frontend.sh"

# -----------------------------------------------------------------------------
# Step 5: Start Backend Services
# -----------------------------------------------------------------------------

log_info ""
log_info "=========================================="
log_info "  Step 5: Start Backend Services"
log_info "=========================================="

cd "${PROJECT_ROOT}/docker"

log_info "Starting all backend services..."
docker compose -f docker-compose.prod.yml up -d

log_info "Waiting for services to start..."
sleep 10

# -----------------------------------------------------------------------------
# Step 6: Configure Nginx
# -----------------------------------------------------------------------------

log_info ""
log_info "=========================================="
log_info "  Step 6: Configure Nginx"
log_info "=========================================="

# Copy Nginx configurations
log_info "Installing Nginx configurations..."
cp "${PROJECT_ROOT}/nginx/movex-api-gateway.conf" /etc/nginx/sites-available/
cp "${PROJECT_ROOT}/nginx/movex-frontend.conf" /etc/nginx/sites-available/

# Enable sites
ln -sf /etc/nginx/sites-available/movex-api-gateway.conf /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/movex-frontend.conf /etc/nginx/sites-enabled/

# Disable default site if exists
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Test and reload Nginx
log_info "Testing Nginx configuration..."
if nginx -t; then
    log_info "Reloading Nginx..."
    systemctl reload nginx
    log_success "Nginx configured successfully"
else
    log_error "Nginx configuration test failed"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 7: Configure Firewall
# -----------------------------------------------------------------------------

log_info ""
log_info "=========================================="
log_info "  Step 7: Configure Firewall"
log_info "=========================================="

bash "${PROJECT_ROOT}/security/firewall-rules.sh"

# -----------------------------------------------------------------------------
# Health Check
# -----------------------------------------------------------------------------

log_info ""
log_info "=========================================="
log_info "  Running Health Checks"
log_info "=========================================="

bash "${SCRIPT_DIR}/utils/health-check.sh"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

log_info ""
log_info "=========================================="
log_success "  Deployment Complete!"
log_info "=========================================="
log_info ""
log_info "Access points:"
log_info "  Frontend:  http://${SERVER_IP:-localhost}:${NGINX_FRONTEND_PORT:-8084}"
log_info "  API:       http://${SERVER_IP:-localhost}:${NGINX_API_PORT:-8080}"
log_info ""
log_info "API Endpoints:"
log_info "  System:      /api/system"
log_info "  Auth:        /api/auth"
log_info "  MasterData:  /api/master-data"
log_info "  OMS:         /api/oms"
log_info "  TMS:         /api/tms"
log_info ""
log_info "Useful commands:"
log_info "  View logs:     docker compose -f docker/docker-compose.prod.yml logs -f"
log_info "  Restart all:   docker compose -f docker/docker-compose.prod.yml restart"
log_info "  Stop all:      docker compose -f docker/docker-compose.prod.yml down"
log_info "  Health check:  ./scripts/utils/health-check.sh"
log_info ""
