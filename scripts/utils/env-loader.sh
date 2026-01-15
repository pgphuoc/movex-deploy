#!/bin/bash
# =============================================================================
# Environment Loader Utility
# Safely loads environment variables from .env file
# =============================================================================

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Load environment variables from .env file
# Searches in order: PROJECT_ROOT/.env, PARENT_DIR/.env.dev, PARENT_DIR/.env
load_env() {
    local env_file=""
    local parent_dir="$(dirname "${PROJECT_ROOT}")"

    # Search for .env file in multiple locations
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        env_file="${PROJECT_ROOT}/.env"
    elif [[ -f "${parent_dir}/.env.dev" ]]; then
        env_file="${parent_dir}/.env.dev"
    elif [[ -f "${parent_dir}/.env" ]]; then
        env_file="${parent_dir}/.env"
    fi

    if [[ -z "$env_file" ]]; then
        log_error ".env file not found. Searched locations:"
        log_error "  - ${PROJECT_ROOT}/.env"
        log_error "  - ${parent_dir}/.env.dev"
        log_error "  - ${parent_dir}/.env"
        log_info "Please create .env file in one of these locations"
        exit 1
    fi

    log_info "Loading environment from: $env_file"
    
    # Read line by line and export manually to handle special chars like $
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Only process lines with KEY=VALUE format (key starts with letter/underscore)
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            # Extract key (everything before first =)
            local key="${line%%=*}"
            # Extract value (everything after first =)
            local value="${line#*=}"
            # Remove trailing whitespace from value
            value="${value%"${value##*[![:space:]]}"}"
            # Export without expansion
            export "$key"="$value"
        fi
    done < "$env_file"
    
    log_success "Environment loaded successfully"
}

# Validate required environment variables
validate_env() {
    local required_vars=("$@")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        exit 1
    fi
    
    log_success "All required environment variables are set"
}

# Check if running as root
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        log_info "Please run with: sudo $0"
        exit 1
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Wait for a service to be healthy
wait_for_service() {
    local host="$1"
    local port="$2"
    local service_name="${3:-Service}"
    local max_attempts="${4:-30}"
    local attempt=1
    
    log_info "Waiting for $service_name to be ready at $host:$port..."
    
    while ! nc -z "$host" "$port" 2>/dev/null; do
        if [[ $attempt -ge $max_attempts ]]; then
            log_error "$service_name is not responding after $max_attempts attempts"
            return 1
        fi
        echo -n "."
        sleep 2
        ((attempt++))
    done
    
    echo ""
    log_success "$service_name is ready!"
    return 0
}

# Create directory if not exists
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_info "Creating directory: $dir"
        mkdir -p "$dir"
    fi
}

# Replace environment variables in config files
# Usage: replace_env_vars <source_file> <target_file>
# Replaces patterns like ${VAR_NAME} or $VAR_NAME with actual values
replace_env_vars() {
    local source_file="$1"
    local target_file="$2"

    if [[ ! -f "$source_file" ]]; then
        log_error "Source file not found: $source_file"
        return 1
    fi

    log_info "Processing: $source_file -> $target_file"

    # Use envsubst if available, otherwise use sed
    if command_exists envsubst; then
        envsubst < "$source_file" > "$target_file"
    else
        # Manual replacement using sed
        cp "$source_file" "$target_file"

        # Replace common variables
        sed -i "s|\${SERVER_IP}|${SERVER_IP:-localhost}|g" "$target_file"
        sed -i "s|\$SERVER_IP|${SERVER_IP:-localhost}|g" "$target_file"
        sed -i "s|YOUR_SERVER_IP|${SERVER_IP:-localhost}|g" "$target_file"

        sed -i "s|\${NGINX_API_PORT}|${NGINX_API_PORT:-8080}|g" "$target_file"
        sed -i "s|\$NGINX_API_PORT|${NGINX_API_PORT:-8080}|g" "$target_file"

        sed -i "s|\${NGINX_FRONTEND_PORT}|${NGINX_FRONTEND_PORT:-8084}|g" "$target_file"
        sed -i "s|\$NGINX_FRONTEND_PORT|${NGINX_FRONTEND_PORT:-8084}|g" "$target_file"

        sed -i "s|\${DB_HOST}|${DB_HOST:-localhost}|g" "$target_file"
        sed -i "s|\${DB_PORT}|${DB_PORT:-5435}|g" "$target_file"
        sed -i "s|\${DB_USER}|${DB_USER:-root}|g" "$target_file"
        sed -i "s|\${DB_PASS}|${DB_PASS:-root}|g" "$target_file"

        sed -i "s|\${REDIS_HOST}|${REDIS_HOST:-localhost}|g" "$target_file"
        sed -i "s|\${REDIS_PORT}|${REDIS_PORT:-6389}|g" "$target_file"
        sed -i "s|\${REDIS_PASSWORD}|${REDIS_PASSWORD:-movex123}|g" "$target_file"
    fi

    log_success "Processed: $target_file"
}

# Process all config files in config/ folder
process_config_files() {
    local config_dir="${PROJECT_ROOT}/config"
    local output_dir="${1:-${PROJECT_ROOT}/config/generated}"

    ensure_dir "$output_dir"

    log_info "Processing config files..."

    for config_file in "$config_dir"/*.env "$config_dir"/*.conf; do
        [[ -f "$config_file" ]] || continue
        local filename=$(basename "$config_file")
        replace_env_vars "$config_file" "$output_dir/$filename"
    done

    log_success "All config files processed to: $output_dir"
}

# Export project root for use in other scripts
export PROJECT_ROOT
export SCRIPT_DIR
