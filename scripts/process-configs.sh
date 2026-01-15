#!/bin/bash
# =============================================================================
# Process Config Files
# Replaces environment variables in config templates
# Usage: ./scripts/process-configs.sh
# =============================================================================

set -euo pipefail

# Load environment utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/env-loader.sh"

log_info "=========================================="
log_info "  Process Config Files"
log_info "=========================================="

# Load environment variables
load_env

# Process all config files
process_config_files

log_info ""
log_info "=========================================="
log_success "  Config Processing Complete!"
log_info "=========================================="
log_info ""
log_info "Generated files are in: ${PROJECT_ROOT}/config/generated/"
log_info ""
log_info "Variables applied:"
log_info "  SERVER_IP:          ${SERVER_IP:-not set}"
log_info "  NGINX_API_PORT:     ${NGINX_API_PORT:-8080}"
log_info "  NGINX_FRONTEND_PORT: ${NGINX_FRONTEND_PORT:-8084}"
log_info ""
