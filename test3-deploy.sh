#!/bin/bash

# ============================================================================
# Deploy Script for test3
# ============================================================================
# This script helps you deploy test3 by prompting for version and environment.
# It calls the deployment workflow in the k8s repository.
#
# Usage:
#   ./test3-deploy.sh
#
# Requirements:
#   - GitHub CLI (gh) installed and authenticated
#   - Access to the k8s repository
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Hardcoded app name
APP_NAME="test3"
SOURCE_REPO="winit-testabc/test3"
GITHUB_ORG="winit-testabc"

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

print_question() {
    echo -e "${YELLOW}?${NC} $1"
}

# Function to read input (handles piped input)
read_input() {
    local prompt_text="$1"
    local var_name="$2"
    local default_value="$3"
    local input_source="/dev/tty"
    local user_input=""
    
    if [ -t 0 ]; then
        read -r -p "$prompt_text" user_input
    elif [ -e "$input_source" ] && [ -r "$input_source" ]; then
        read -r -p "$prompt_text" user_input < "$input_source"
    else
        print_error "Cannot read from terminal. Please run the script directly."
        exit 1
    fi
    
    # Use default if input is empty
    if [ -z "$user_input" ] && [ -n "$default_value" ]; then
        user_input="$default_value"
    fi
    
    # Set the variable using eval (safe because we control the var_name)
    eval "$var_name=\"$user_input\""
}

# Prompt for environment
prompt_environment() {
    while true; do
        print_question "Select environment (production/staging) [default: production]: "
        read_input "Select environment (production/staging) [default: production]: " ENV_INPUT "production"
        
        ENV=$(echo "$ENV_INPUT" | tr '[:upper:]' '[:lower:]')
        
        if [ "$ENV" = "production" ] || [ "$ENV" = "prod" ]; then
            ENV_SUFFIX="prod"
            break
        elif [ "$ENV" = "staging" ] || [ "$ENV" = "stage" ]; then
            ENV_SUFFIX="staging"
            break
        else
            print_error "Invalid environment. Please enter 'production' or 'staging'."
        fi
    done
}

# Get latest version tag from k8s repository
get_latest_version() {
    local env_suffix="${ENV_SUFFIX}"
    local app_name="test3"
    
    # Determine k8s repo based on environment
    if [ "$env_suffix" = "staging" ]; then
        local k8s_repo="${GITHUB_ORG}/k8s-staging"
    else
        local k8s_repo="${GITHUB_ORG}/k8s-production"
    fi
    
    # Get all tags matching the pattern v*.*.*-{app_name}-{env}
    # Format: v1.0.0-test3-prod or v1.0.0-test3-staging
    # Use gh api to get tags and filter properly
    # Note: app_name and env_suffix are local variables, so we use $app_name (not ${app_name})
    local latest_version=$(gh api repos/${k8s_repo}/git/refs/tags --jq ".[].ref" 2>/dev/null | \
        grep -E "refs/tags/v[0-9]+\.[0-9]+\.[0-9]+-$app_name-$env_suffix$" | \
        sed "s|refs/tags/v||" | \
        sed "s/-$app_name-$env_suffix$//" | \
        sort -V -t. -k1,1n -k2,2n -k3,3n | \
        tail -1)
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "" ]; then
        echo "1.0.0"
    else
        echo "$latest_version"
    fi
}

# Increment version (patch version)
increment_version() {
    local version="$1"
    local major=$(echo "$version" | cut -d. -f1)
    local minor=$(echo "$version" | cut -d. -f2)
    local patch=$(echo "$version" | cut -d. -f3)
    
    patch=$((patch + 1))
    echo "${major}.${minor}.${patch}"
}

# Check for pending changes and ask to commit
check_pending_changes() {
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        return 0
    fi
    
    # Check for uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        echo ""
        print_warning "You have uncommitted changes:"
        git status --short
        echo ""
        print_question "Do you want to commit these changes before deploying? (Y/n): "
        read_input "Do you want to commit these changes before deploying? (Y/n): " COMMIT_CHANGES "Y"
        
        if [[ "$COMMIT_CHANGES" =~ ^[Yy]?$ ]]; then
            print_question "Enter commit message [default: WIP: prepare for deployment]: "
            read_input "Enter commit message [default: WIP: prepare for deployment]: " COMMIT_MSG "WIP: prepare for deployment"
            
            git add -A
            git commit -m "$COMMIT_MSG" || {
                print_error "Failed to commit changes"
                exit 1
            }
            
            print_question "Do you want to push these changes? (Y/n): "
            read_input "Do you want to push these changes? (Y/n): " PUSH_CHANGES "Y"
            
            if [[ "$PUSH_CHANGES" =~ ^[Yy]?$ ]]; then
                git push || {
                    print_error "Failed to push changes"
                    exit 1
                }
                print_success "Changes pushed"
            fi
        fi
    fi
}

# Prompt for version with auto-increment
prompt_version() {
    # Get latest version for the selected environment
    local latest_version=$(get_latest_version)
    local suggested_version=$(increment_version "$latest_version")
    
    print_info "Latest version for ${ENV_SUFFIX}: v${latest_version}"
    print_question "Enter version number [default: ${suggested_version}]: "
    read_input "Enter version number [default: ${suggested_version}]: " VERSION_INPUT "$suggested_version"
    
    # Remove 'v' prefix if present
    VERSION=$(echo "$VERSION_INPUT" | sed 's/^v//')
    
    # Validate version format (basic check)
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        print_error "Invalid version format. Expected format: X.Y.Z (e.g., 1.0.0)"
        exit 1
    fi
    
    # Tag format for workflow dispatch: v{VERSION}-{ENV}
    # The deploy script passes service_name separately to the workflow
    # Example: v1.0.0-prod
    TAG="v${VERSION}-${ENV_SUFFIX}"
    
    # Also create a tag on k8s repository for version detection: v{VERSION}-{APP_NAME}-{ENV}
    # This tag is used by version detection to find the latest version
    K8S_TAG="v${VERSION}-test3-${ENV_SUFFIX}"
}

# Monitor deployment workflow by run ID
monitor_deployment_by_id() {
    local run_id="$1"
    local env_suffix="${ENV_SUFFIX}"
    
    # Determine k8s repo based on environment
    if [ "$env_suffix" = "staging" ]; then
        local k8s_repo="${GITHUB_ORG}/k8s-staging"
    else
        local k8s_repo="${GITHUB_ORG}/k8s-production"
    fi
    
    if [ -z "$run_id" ]; then
        print_warning "No run ID provided for monitoring"
        return 0
    fi
    
    local run_url="https://github.com/$k8s_repo/actions/runs/$run_id"
    print_info "Monitoring workflow run #${run_id}"
    print_info "Workflow run URL: $run_url"
    echo ""
    
    # Watch the workflow run
    gh run watch "$run_id" --repo "$k8s_repo" --exit-status
    
    local exit_code=$?
    echo ""
    if [ $exit_code -eq 0 ]; then
        print_success "Deployment completed successfully!"
        echo ""
        print_info "View workflow run: $run_url"
    else
        print_error "Deployment failed with exit code $exit_code"
        echo ""
        print_info "View workflow run: $run_url"
        exit $exit_code
    fi
}

# Main execution
main() {
    echo ""
    echo "============================================================================="
    echo "🚀 Deploy test3"
    echo "============================================================================="
    echo ""
    
    # Check for pending changes
    check_pending_changes
    
    prompt_environment
    prompt_version
    
    echo ""
    print_info "Deployment details:"
    echo "  App: test3"
    echo "  Version: ${TAG}"
    echo "  Environment: ${ENV_SUFFIX}"
    echo "  Source Repo: "
    echo ""
    
    # Find WinIT-DO directory (assumes app repo is cloned alongside WinIT-DO)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Try common locations for WinIT-DO
    WINIT_DO_DIRS=(
        "$(dirname "$SCRIPT_DIR")/WinIT-DO"
        "$(dirname "$(dirname "$SCRIPT_DIR")")/WinIT-DO"
        "$HOME/WinIT-DO"
        "."
    )
    
    DEPLOY_SCRIPT=""
    for dir in "${WINIT_DO_DIRS[@]}"; do
        if [ -f "$dir/scripts/deploy-app.sh" ]; then
            DEPLOY_SCRIPT="$dir/scripts/deploy-app.sh"
            break
        fi
    done
    
    if [ -z "$DEPLOY_SCRIPT" ] || [ ! -f "$DEPLOY_SCRIPT" ]; then
        print_error "Could not find deploy-app.sh script"
        print_info ""
        print_info "Please ensure WinIT-DO repository is cloned and accessible."
        print_info ""
        print_info "You can deploy manually using:"
        echo "  cd WinIT-DO"
        echo "  ./scripts/deploy-app.sh test3 ${TAG} "
        exit 1
    fi
    
    print_info "Running deployment script..."
    echo ""
    
    # Execute deploy script and capture output to extract run ID
    # Auto-confirm the prompt by piping 'y' to stdin
    local deploy_output=$(echo "y" | bash "$DEPLOY_SCRIPT" "test3" "${TAG}" "" 2>&1)
    local deploy_exit=$?
    
    # Extract workflow run ID from output (look for "actions/runs/" URL)
    local run_id=$(echo "$deploy_output" | grep -oE "actions/runs/[0-9]+" | head -1 | sed 's|actions/runs/||')
    
    # Also try to extract from "Workflow run:" line
    if [ -z "$run_id" ]; then
        run_id=$(echo "$deploy_output" | grep -oE "runs/[0-9]+" | head -1 | sed 's|runs/||')
    fi
    
    # If deploy script failed, exit
    if [ $deploy_exit -ne 0 ]; then
        echo "$deploy_output"
        exit $deploy_exit
    fi
    
    echo "$deploy_output"
    echo ""
    
    # Create and push tag to k8s repository for version tracking
    # This allows version detection to work correctly
    print_info "Creating version tag on k8s repository..."
    local k8s_repo="${GITHUB_ORG}/k8s-production"
    if [ "${ENV_SUFFIX}" = "staging" ]; then
        k8s_repo="${GITHUB_ORG}/k8s-staging"
    fi
    
    # Create tag directly using gh CLI (faster than cloning)
    # This creates a lightweight tag on the k8s repository
    print_info "Creating version tag ${K8S_TAG} on $k8s_repo..."
    if gh api repos/${k8s_repo}/git/refs -X POST -f ref="refs/tags/${K8S_TAG}" -f sha="$(gh api repos/${k8s_repo}/git/ref/heads/main --jq .object.sha)" 2>/dev/null; then
        print_success "Tag ${K8S_TAG} created on $k8s_repo"
    elif gh api repos/${k8s_repo}/git/refs/tags/${K8S_TAG} -X PATCH -f sha="$(gh api repos/${k8s_repo}/git/ref/heads/main --jq .object.sha)" 2>/dev/null; then
        print_success "Tag ${K8S_TAG} updated on $k8s_repo"
    else
        print_warning "Could not create tag ${K8S_TAG} on $k8s_repo (may need manual creation)"
    fi
    
    # Monitor the deployment if we found a run ID
    if [ -n "$run_id" ]; then
        monitor_deployment_by_id "$run_id"
    else
        print_warning "Could not extract workflow run ID from output"
        print_info "You can monitor manually:"
        echo "  gh run list --repo $k8s_repo --workflow=deploy-from-tag.yml"
    fi
}

main "$@"
