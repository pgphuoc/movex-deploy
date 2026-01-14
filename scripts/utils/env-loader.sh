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
load_env() {
    local env_file="${PROJECT_ROOT}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        log_error ".env file not found at: $env_file"
        log_info "Please copy .env.example to .env and configure it:"
        log_info "  cp ${PROJECT_ROOT}/.env.example ${PROJECT_ROOT}/.env"
        exit 1
    fi
    
    log_info "Loading environment from: $env_file"
    
    # Export variables from .env file (ignoring comments and empty lines)
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        # Skip comments (lines starting with #)
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        # Skip lines without = sign
        [[ "$line" != *"="* ]] && continue
        
        # Extract key and value
        key="${line%%=*}"
        value="${line#*=}"
        
        # Remove leading/trailing whitespace from key
        key=$(echo "$key" | xargs)
        
        # Skip if key is empty or starts with #
        [[ -z "$key" ]] && continue
        [[ "$key" =~ ^# ]] && continue
        
        # Export the variable
        export "$key"="$value"
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

# Export project root for use in other scripts
export PROJECT_ROOT
export SCRIPT_DIR
