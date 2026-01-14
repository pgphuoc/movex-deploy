#!/bin/bash
# =============================================================================
# MoveX Health Check Script
# Checks the health of all deployed services
# =============================================================================

set -euo pipefail

# Load environment utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env-loader.sh"

# Load environment (optional, will use defaults if not available)
load_env 2>/dev/null || true

log_info "=========================================="
log_info "  MoveX Health Check"
log_info "=========================================="

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
API_HOST="${SERVER_IP:-localhost}"
API_PORT="${NGINX_API_PORT:-8080}"
FRONTEND_PORT="${NGINX_FRONTEND_PORT:-8084}"

# Internal service ports (Docker)
SYSTEM_PORT="${PORT_SYSTEM:-8180}"
MASTERDATA_PORT="${PORT_MASTERDATA:-8181}"
OMS_PORT="${PORT_OMS:-8182}"
TMS_PORT="${PORT_TMS:-8183}"
AUTH_PORT="${PORT_AUTH:-8185}"

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5435}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6389}"

# -----------------------------------------------------------------------------
# Health Check Functions
# -----------------------------------------------------------------------------

check_http_health() {
    local name="$1"
    local url="$2"
    local timeout="${3:-5}"
    
    printf "  %-20s" "${name}:"
    
    if curl -sf --max-time "${timeout}" "${url}" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ UP${NC}"
        return 0
    else
        echo -e "${RED}✗ DOWN${NC}"
        return 1
    fi
}

check_tcp_port() {
    local name="$1"
    local host="$2"
    local port="$3"
    
    printf "  %-20s" "${name}:"
    
    if nc -z "${host}" "${port}" 2>/dev/null; then
        echo -e "${GREEN}✓ UP${NC} (${host}:${port})"
        return 0
    else
        echo -e "${RED}✗ DOWN${NC} (${host}:${port})"
        return 1
    fi
}

check_docker_container() {
    local name="$1"
    local container="$2"
    
    printf "  %-20s" "${name}:"
    
    local status=$(docker inspect --format='{{.State.Status}}' "${container}" 2>/dev/null || echo "not found")
    
    if [[ "${status}" == "running" ]]; then
        echo -e "${GREEN}✓ Running${NC}"
        return 0
    else
        echo -e "${RED}✗ ${status}${NC}"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Check Infrastructure
# -----------------------------------------------------------------------------

log_info ""
log_info "Infrastructure Services:"

INFRA_OK=0
check_tcp_port "PostgreSQL" "${DB_HOST}" "${DB_PORT}" || ((INFRA_OK++))
check_tcp_port "Redis" "${REDIS_HOST}" "${REDIS_PORT}" || ((INFRA_OK++))

# -----------------------------------------------------------------------------
# Check Docker Containers
# -----------------------------------------------------------------------------

log_info ""
log_info "Docker Containers:"

DOCKER_OK=0
check_docker_container "DB Container" "movex_postgres" || ((DOCKER_OK++))
check_docker_container "Redis Container" "movex_redis" || ((DOCKER_OK++))
check_docker_container "System Service" "movex_system" || ((DOCKER_OK++))
check_docker_container "MasterData Service" "movex_masterdata" || ((DOCKER_OK++))
check_docker_container "OMS Service" "movex_oms" || ((DOCKER_OK++))
check_docker_container "TMS Service" "movex_tms" || ((DOCKER_OK++))
check_docker_container "Auth Service" "movex_auth" || ((DOCKER_OK++))

# -----------------------------------------------------------------------------
# Check Backend Services (via internal ports)
# -----------------------------------------------------------------------------

log_info ""
log_info "Backend Services (Internal):"

BE_OK=0
check_http_health "System" "http://localhost:${SYSTEM_PORT}/actuator/health" || ((BE_OK++))
check_http_health "Auth" "http://localhost:${AUTH_PORT}/actuator/health" || ((BE_OK++))
check_http_health "MasterData" "http://localhost:${MASTERDATA_PORT}/actuator/health" || ((BE_OK++))
check_http_health "OMS" "http://localhost:${OMS_PORT}/actuator/health" || ((BE_OK++))
check_http_health "TMS" "http://localhost:${TMS_PORT}/actuator/health" || ((BE_OK++))

# -----------------------------------------------------------------------------
# Check Nginx Gateway
# -----------------------------------------------------------------------------

log_info ""
log_info "Nginx Gateway (External):"

NGINX_OK=0
check_tcp_port "API Gateway" "${API_HOST}" "${API_PORT}" || ((NGINX_OK++))
check_tcp_port "Frontend" "${API_HOST}" "${FRONTEND_PORT}" || ((NGINX_OK++))

# Check API routing via Nginx
log_info ""
log_info "API Routes (via Nginx):"

API_OK=0
check_http_health "GET /api/system" "http://${API_HOST}:${API_PORT}/api/system/actuator/health" || ((API_OK++))
check_http_health "GET /api/auth" "http://${API_HOST}:${API_PORT}/api/auth/actuator/health" || ((API_OK++))
check_http_health "GET /api/master-data" "http://${API_HOST}:${API_PORT}/api/master-data/actuator/health" || ((API_OK++))
check_http_health "GET /api/oms" "http://${API_HOST}:${API_PORT}/api/oms/actuator/health" || ((API_OK++))
check_http_health "GET /api/tms" "http://${API_HOST}:${API_PORT}/api/tms/actuator/health" || ((API_OK++))

# Check Frontend
log_info ""
log_info "Frontend:"

FE_OK=0
check_http_health "Frontend App" "http://${API_HOST}:${FRONTEND_PORT}/" || ((FE_OK++))

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

log_info ""
log_info "=========================================="

TOTAL_ISSUES=$((INFRA_OK + DOCKER_OK + BE_OK + NGINX_OK + API_OK + FE_OK))

if [[ ${TOTAL_ISSUES} -eq 0 ]]; then
    log_success "  All Services Healthy!"
else
    log_error "  ${TOTAL_ISSUES} issue(s) detected"
    log_info ""
    log_info "Troubleshooting commands:"
    log_info "  View logs:    docker compose -f docker/docker-compose.prod.yml logs -f"
    log_info "  Restart:      docker compose -f docker/docker-compose.prod.yml restart"
    log_info "  Check nginx:  nginx -t && systemctl status nginx"
fi

log_info "=========================================="
log_info ""

exit ${TOTAL_ISSUES}
