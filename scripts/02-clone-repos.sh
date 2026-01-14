#!/bin/bash
# =============================================================================
# MoveX Repository Clone Script
# Clones all MoveX repositories from GitHub
# =============================================================================

set -euo pipefail

# Load environment utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/env-loader.sh"

# Load environment variables
load_env

# Validate required environment variables
validate_env GITHUB_TOKEN GITHUB_ORG GITHUB_BRANCH

log_info "=========================================="
log_info "  MoveX Repository Clone Script"
log_info "  Branch: ${GITHUB_BRANCH}"
log_info "=========================================="

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SRC_DIR="${DEPLOY_DIR:-/opt/movex}/src"
GITHUB_BASE_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_ORG}"

# Repository list - Backend services
BE_REPOS=(
    "movex-be-core"
    "movex-be-migration"
    "movex-be-system"
    "movex-be-masterdata"
    "movex-be-oms"
    "movex-be-tms"
    "movex-be-auth"
)

# Repository list - Frontend projects
FE_REPOS=(
    "movex-fe-masterdata"
    "movex-fe-system"
    "movex-fe-boilerplate"
)

# All repositories
ALL_REPOS=("${BE_REPOS[@]}" "${FE_REPOS[@]}")

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

clone_or_update_repo() {
    local repo_name="$1"
    local repo_url="${GITHUB_BASE_URL}/${repo_name}.git"
    local repo_dir="${SRC_DIR}/${repo_name}"
    
    if [[ -d "${repo_dir}/.git" ]]; then
        log_info "Updating existing repository: ${repo_name}"
        cd "${repo_dir}"
        
        # Fetch all branches
        git fetch --all --prune
        
        # Try to checkout the target branch
        if git show-ref --verify --quiet "refs/remotes/origin/${GITHUB_BRANCH}"; then
            git checkout "${GITHUB_BRANCH}" 2>/dev/null || git checkout -b "${GITHUB_BRANCH}" "origin/${GITHUB_BRANCH}"
            git pull origin "${GITHUB_BRANCH}"
            log_success "Updated ${repo_name} to branch ${GITHUB_BRANCH}"
        else
            log_warning "Branch ${GITHUB_BRANCH} not found in ${repo_name}, using default branch"
            git checkout main 2>/dev/null || git checkout master 2>/dev/null || true
            git pull
        fi
    else
        log_info "Cloning repository: ${repo_name}"
        
        # Remove directory if it exists but is not a git repo
        [[ -d "${repo_dir}" ]] && rm -rf "${repo_dir}"
        
        # Clone with specific branch
        if git clone --branch "${GITHUB_BRANCH}" --single-branch "${repo_url}" "${repo_dir}" 2>/dev/null; then
            log_success "Cloned ${repo_name} (branch: ${GITHUB_BRANCH})"
        else
            # If branch doesn't exist, clone default and try to checkout
            log_warning "Branch ${GITHUB_BRANCH} not found, cloning default branch..."
            git clone "${repo_url}" "${repo_dir}"
            cd "${repo_dir}"
            
            # Try to checkout the target branch if it exists
            git fetch --all
            if git show-ref --verify --quiet "refs/remotes/origin/${GITHUB_BRANCH}"; then
                git checkout "${GITHUB_BRANCH}"
                log_success "Cloned ${repo_name} and switched to ${GITHUB_BRANCH}"
            else
                log_warning "Using default branch for ${repo_name}"
            fi
        fi
    fi
}

push_env_changes() {
    local repo_name="$1"
    local repo_dir="${SRC_DIR}/${repo_name}"
    
    if [[ ! -d "${repo_dir}/.git" ]]; then
        log_warning "Not a git repo: ${repo_dir}"
        return 1
    fi
    
    cd "${repo_dir}"
    
    # Check if there are changes to .env file
    if git status --porcelain | grep -q "\.env"; then
        log_info "Committing .env changes for ${repo_name}..."
        
        git add .env 2>/dev/null || true
        git add .env.* 2>/dev/null || true
        
        if git diff --cached --quiet; then
            log_info "No .env changes to commit for ${repo_name}"
            return 0
        fi
        
        git commit -m "chore: Update environment configuration for deployment"
        
        log_info "Pushing changes to origin..."
        if git push origin "$(git branch --show-current)"; then
            log_success "Pushed .env changes for ${repo_name}"
        else
            log_error "Failed to push ${repo_name}"
            return 1
        fi
    else
        log_info "No .env changes for ${repo_name}"
    fi
}

push_all_changes() {
    log_info ""
    log_info "=========================================="
    log_info "  Pushing Environment Changes to Origin"
    log_info "=========================================="
    
    for repo in "${ALL_REPOS[@]}"; do
        push_env_changes "${repo}" || true
    done
    
    log_success "All changes pushed to origin"
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

# Create source directory
ensure_dir "${SRC_DIR}"

log_info ""
log_info "Cloning ${#ALL_REPOS[@]} repositories to: ${SRC_DIR}"
log_info ""

# Clone/update all repositories
SUCCESS_COUNT=0
FAIL_COUNT=0

for repo in "${ALL_REPOS[@]}"; do
    log_info "----------------------------------------"
    if clone_or_update_repo "$repo"; then
        ((SUCCESS_COUNT++))
    else
        log_error "Failed to clone/update: $repo"
        ((FAIL_COUNT++))
    fi
done

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

log_info ""
log_info "=========================================="
log_info "  Clone Summary"
log_info "=========================================="
log_info ""
log_success "Successfully cloned/updated: ${SUCCESS_COUNT} repositories"
[[ $FAIL_COUNT -gt 0 ]] && log_error "Failed: ${FAIL_COUNT} repositories"
log_info ""
log_info "Repository locations:"
for repo in "${ALL_REPOS[@]}"; do
    if [[ -d "${SRC_DIR}/${repo}/.git" ]]; then
        BRANCH=$(cd "${SRC_DIR}/${repo}" && git branch --show-current)
        log_info "  ✓ ${repo} (${BRANCH})"
    else
        log_error "  ✗ ${repo} (not cloned)"
    fi
done
log_info ""
log_info "Next step: Run ./03-build-services.sh"
