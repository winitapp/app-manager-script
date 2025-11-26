#!/bin/bash

# ============================================================================
# App Manager Script - Installer
# ============================================================================
# Quick installer that downloads and runs the script
# ============================================================================

set -e

REPO="winit-testabc/app-manager-script"
SCRIPT_URL="https://raw.githubusercontent.com/${REPO}/main/setup-app.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✅${NC} $1"; }
print_error() { echo -e "${RED}❌${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠️${NC} $1"; }

# Check if GitHub CLI is available
if command -v gh &> /dev/null && gh auth status &> /dev/null; then
    print_info "Using GitHub CLI to download script..."
    
    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Clone the repo (gh handles authentication automatically)
    if gh repo clone "$REPO" -- --depth=1 2>/dev/null; then
        cd app-manager-script
        
        if [ -f "setup-app.sh" ]; then
            chmod +x setup-app.sh
            print_success "Script downloaded successfully"
            exec ./setup-app.sh
        else
            print_error "Script not found"
            exit 1
        fi
    else
        print_error "Failed to clone repository"
        print_info "Make sure you have access to the repository"
        exit 1
    fi
    
elif [ -n "$GITHUB_TOKEN" ]; then
    print_info "Using GitHub token to download script..."
    
    TEMP_FILE=$(mktemp)
    
    if curl -H "Authorization: token $GITHUB_TOKEN" \
        -fsSL "$SCRIPT_URL" \
        -o "$TEMP_FILE" 2>/dev/null; then
        chmod +x "$TEMP_FILE"
        print_success "Script downloaded successfully"
        exec "$TEMP_FILE"
    else
        print_error "Failed to download script"
        print_info "Make sure GITHUB_TOKEN is set and has 'repo' scope"
        exit 1
    fi
    
else
    print_error "Cannot download script from private repository"
    echo ""
    echo "Options:"
    echo "  1. Install GitHub CLI and authenticate:"
    echo "     brew install gh  # or apt install gh"
    echo "     gh auth login"
    echo ""
    echo "  2. Set GITHUB_TOKEN environment variable:"
    echo "     export GITHUB_TOKEN=ghp_your_token_here"
    echo ""
    echo "  3. Clone the repository manually:"
    echo "     git clone https://github.com/${REPO}.git"
    echo "     cd app-manager-script"
    echo "     ./setup-app.sh"
    echo ""
    exit 1
fi

