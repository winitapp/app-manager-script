#!/bin/bash

# ============================================================================
# App Configuration Script
# ============================================================================
# Interactive script to configure new apps or edit existing ones
# Creates/updates Kubernetes manifests and ingress routes
# Commits and pushes changes to GitHub
#
# Usage:
#   ./setup-app.sh
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✅${NC} $1"; }
print_error() { echo -e "${RED}❌${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠️${NC} $1"; }
print_question() { echo -e "${CYAN}?${NC} $1"; }
print_menu() { echo -e "${MAGENTA}→${NC} $1"; }

# Helper function to read input (handles piping)
read_input() {
    if [ -t 0 ]; then
        # stdin is a terminal, read normally
        read -r "$@"
    elif [ -e /dev/tty ] && [ -r /dev/tty ]; then
        # stdin is piped, but /dev/tty exists and is readable
        read -r "$@" < /dev/tty
    else
        # /dev/tty not available, try to read from stderr's terminal
        # This is a fallback for environments where /dev/tty doesn't work
        if [ -t 2 ]; then
            read -r "$@" <&2
        else
            # Last resort: try /dev/tty anyway (might work in some cases)
            read -r "$@" < /dev/tty 2>/dev/null || {
                print_error "Cannot read from terminal. Please download and run the script:"
                echo "  curl -fsSL https://raw.githubusercontent.com/winit-testabc/app-manager-script/main/setup-app.sh -o setup-app.sh"
                echo "  chmod +x setup-app.sh"
                echo "  ./setup-app.sh"
                exit 1
            }
        fi
    fi
}

# Configuration
GITHUB_ORG="winit-testabc"
K8S_REPO="${GITHUB_ORG}/k8s-production"
K8S_DIR="k8s-production/apps"
INGRESS_FILE="k8s-production/apps/tunnel-ingress/tunnel-ingress.yaml"
ECR_REGISTRY="418295680544.dkr.ecr.us-east-1.amazonaws.com/winitxyz"

# Global variables
APP_NAME=""
ENVIRONMENT="production"
NAMESPACE="production"
MANIFEST_FILE=""
APP_EXISTS=false
CHANGES_MADE=false

# Check if GitHub CLI is installed
check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is not installed"
        echo ""
        echo "Install it:"
        echo "  macOS:   brew install gh"
        echo "  Linux:   apt install gh"
        echo "  Windows: winget install GitHub.cli"
        echo ""
        echo "Then authenticate:"
        echo "  gh auth login"
        exit 1
    fi
    
    if ! gh auth status &> /dev/null; then
        print_error "Not authenticated with GitHub CLI"
        echo ""
        echo "Authenticate:"
        echo "  gh auth login"
        exit 1
    fi
}

# Clone k8s-production repository if it doesn't exist
setup_k8s_repo() {
    WORK_DIR="$(pwd)"
    
    if [ -d "k8s-production" ]; then
        print_info "k8s-production directory exists locally"
        print_info "Updating from remote..."
        cd k8s-production
        git fetch origin
        git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || true
        cd "$WORK_DIR"
        return 0
    fi
    
    print_info "k8s-production not found locally. Cloning..."
    
    if gh repo view "$K8S_REPO" &> /dev/null; then
        if gh repo clone "$K8S_REPO" 2>&1; then
            print_success "Cloned k8s-production repository"
        else
            print_error "Failed to clone k8s-production repository"
            echo ""
            echo "You can clone it manually:"
            echo "  gh repo clone $K8S_REPO"
            exit 1
        fi
    else
        print_error "Repository $K8S_REPO not found or not accessible"
        exit 1
    fi
}

# Check if app exists
check_app_exists() {
    MANIFEST_FILE="${K8S_DIR}/${APP_NAME}/${APP_NAME}.yaml"
    if [ -f "$MANIFEST_FILE" ]; then
        APP_EXISTS=true
        # Extract current values from manifest
        extract_current_values
        return 0
    fi
    return 1
}

# Extract current values from existing manifest
extract_current_values() {
    if [ ! -f "$MANIFEST_FILE" ]; then
        return
    fi
    
    # Extract namespace
    NAMESPACE=$(grep -A 5 "kind: Deployment" "$MANIFEST_FILE" | grep "namespace:" | awk '{print $2}' | head -1)
    if [ "$NAMESPACE" = "production" ]; then
        ENVIRONMENT="production"
    elif [ "$NAMESPACE" = "staging" ]; then
        ENVIRONMENT="staging"
    fi
    
    # Extract replicas
    REPLICAS=$(grep "replicas:" "$MANIFEST_FILE" | awk '{print $2}' | head -1)
    
    # Extract container port
    CONTAINER_PORT=$(grep "containerPort:" "$MANIFEST_FILE" | awk '{print $2}' | head -1)
    
    # Extract resources
    MEMORY_REQUEST=$(grep -A 10 "resources:" "$MANIFEST_FILE" | grep "memory:" | head -1 | awk '{print $2}' | tr -d '"')
    MEMORY_LIMIT=$(grep -A 10 "resources:" "$MANIFEST_FILE" | grep "memory:" | tail -1 | awk '{print $2}' | tr -d '"')
    CPU_REQUEST=$(grep -A 10 "resources:" "$MANIFEST_FILE" | grep "cpu:" | head -1 | awk '{print $2}' | tr -d '"')
    CPU_LIMIT=$(grep -A 10 "resources:" "$MANIFEST_FILE" | grep "cpu:" | tail -1 | awk '{print $2}' | tr -d '"')
}

# Prompt for app name
prompt_app_name() {
    while true; do
        print_question "Enter app name:"
        read_input APP_NAME
        
        if [ -z "$APP_NAME" ]; then
            print_error "App name cannot be empty"
            continue
        fi
        
        if [[ ! "$APP_NAME" =~ ^[a-z0-9-]+$ ]]; then
            print_error "App name must be lowercase alphanumeric with hyphens only"
            continue
        fi
        
        break
    done
    
    MANIFEST_FILE="${K8S_DIR}/${APP_NAME}/${APP_NAME}.yaml"
    
    if check_app_exists; then
        print_success "App '$APP_NAME' found (existing app)"
        echo ""
        echo "Current configuration:"
        echo "  Environment: $ENVIRONMENT (namespace: $NAMESPACE)"
        echo "  Replicas: $REPLICAS"
        echo "  Container Port: $CONTAINER_PORT"
        echo "  Resources: ${MEMORY_REQUEST}/${MEMORY_LIMIT} memory, ${CPU_REQUEST}/${CPU_LIMIT} CPU"
        echo ""
    else
        print_info "App '$APP_NAME' not found (new app)"
    fi
}

# Prompt for environment
prompt_environment() {
    if [ "$APP_EXISTS" = true ] && [ -n "$ENVIRONMENT" ]; then
        print_question "Environment [current: $ENVIRONMENT] (press Enter to keep, or enter new):"
        read_input ENV_INPUT
        
        if [ -z "$ENV_INPUT" ]; then
            return 0
        fi
    else
        print_question "Configure for which environment? (production/staging) [default: production]:"
        read_input ENV_INPUT
    fi
    
    if [ -z "$ENV_INPUT" ]; then
        ENVIRONMENT="production"
        NAMESPACE="production"
    else
        ENV_LOWER=$(echo "$ENV_INPUT" | tr '[:upper:]' '[:lower:]')
        if [ "$ENV_LOWER" = "production" ] || [ "$ENV_LOWER" = "prod" ]; then
            ENVIRONMENT="production"
            NAMESPACE="production"
        elif [ "$ENV_LOWER" = "staging" ] || [ "$ENV_LOWER" = "stage" ]; then
            ENVIRONMENT="staging"
            NAMESPACE="staging"
        else
            print_error "Invalid environment. Using production"
            ENVIRONMENT="production"
            NAMESPACE="production"
        fi
    fi
}

# Prompt for replicas
prompt_replicas() {
    if [ "$APP_EXISTS" = true ] && [ -n "$REPLICAS" ]; then
        print_question "Number of replicas [current: $REPLICAS] (press Enter to keep):"
        read_input REPLICAS_INPUT
    else
        print_question "Enter number of replicas [default: 1]:"
        read_input REPLICAS_INPUT
    fi
    
    if [ -z "$REPLICAS_INPUT" ]; then
        REPLICAS="${REPLICAS:-1}"
    else
        REPLICAS="$REPLICAS_INPUT"
        if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]] || [ "$REPLICAS" -lt 1 ]; then
            print_warning "Invalid input, using default: 1"
            REPLICAS=1
        fi
    fi
}

# Prompt for resources
prompt_resources() {
    if [ "$APP_EXISTS" = true ]; then
        print_question "Memory request [current: $MEMORY_REQUEST] (press Enter to keep):"
        read_input MEMORY_REQUEST_INPUT
        MEMORY_REQUEST="${MEMORY_REQUEST_INPUT:-$MEMORY_REQUEST}"
        
        print_question "Memory limit [current: $MEMORY_LIMIT] (press Enter to keep):"
        read_input MEMORY_LIMIT_INPUT
        MEMORY_LIMIT="${MEMORY_LIMIT_INPUT:-$MEMORY_LIMIT}"
        
        print_question "CPU request [current: $CPU_REQUEST] (press Enter to keep):"
        read_input CPU_REQUEST_INPUT
        CPU_REQUEST="${CPU_REQUEST_INPUT:-$CPU_REQUEST}"
        
        print_question "CPU limit [current: $CPU_LIMIT] (press Enter to keep):"
        read_input CPU_LIMIT_INPUT
        CPU_LIMIT="${CPU_LIMIT_INPUT:-$CPU_LIMIT}"
    else
        print_question "Enter memory request [default: 256Mi]:"
        read_input MEMORY_REQUEST_INPUT
        MEMORY_REQUEST="${MEMORY_REQUEST_INPUT:-256Mi}"
        
        print_question "Enter memory limit [default: 512Mi]:"
        read_input MEMORY_LIMIT_INPUT
        MEMORY_LIMIT="${MEMORY_LIMIT_INPUT:-512Mi}"
        
        print_question "Enter CPU request [default: 100m]:"
        read_input CPU_REQUEST_INPUT
        CPU_REQUEST="${CPU_REQUEST_INPUT:-100m}"
        
        print_question "Enter CPU limit [default: 250m]:"
        read_input CPU_LIMIT_INPUT
        CPU_LIMIT="${CPU_LIMIT_INPUT:-250m}"
    fi
}

# Prompt for container port
prompt_container_port() {
    if [ "$APP_EXISTS" = true ] && [ -n "$CONTAINER_PORT" ]; then
        print_question "Container port [current: $CONTAINER_PORT] (press Enter to keep):"
        read_input CONTAINER_PORT_INPUT
    else
        print_question "Enter container port [default: 3000]:"
        read_input CONTAINER_PORT_INPUT
    fi
    
    CONTAINER_PORT="${CONTAINER_PORT_INPUT:-${CONTAINER_PORT:-3000}}"
    
    if ! [[ "$CONTAINER_PORT" =~ ^[0-9]+$ ]]; then
        print_warning "Invalid port, using default: 3000"
        CONTAINER_PORT=3000
    fi
}

# List existing ingress routes for app
list_ingress_routes() {
    if [ ! -f "$INGRESS_FILE" ]; then
        return
    fi
    
    INGRESS_ROUTES=()
    while IFS= read -r line; do
        if echo "$line" | grep -q "host:" && echo "$line" | grep -q "$APP_NAME"; then
            DOMAIN=$(echo "$line" | awk '{print $2}')
            # Find the port for this domain
            PORT_LINE=$(grep -A 10 "host: $DOMAIN" "$INGRESS_FILE" | grep "number:" | head -1)
            PORT=$(echo "$PORT_LINE" | awk '{print $2}')
            INGRESS_ROUTES+=("$DOMAIN:$PORT")
        fi
    done < <(grep -B 5 -A 10 "name: $APP_NAME" "$INGRESS_FILE" | grep "host:")
}

# Manage ingress routes menu
manage_ingress_menu() {
    while true; do
        echo ""
        echo "============================================================================"
        echo "Ingress Routes Management for $APP_NAME"
        echo "============================================================================"
        
        list_ingress_routes
        
        if [ ${#INGRESS_ROUTES[@]} -eq 0 ]; then
            echo "No ingress routes configured."
        else
            echo ""
            echo "Current ingress routes:"
            for i in "${!INGRESS_ROUTES[@]}"; do
                ROUTE="${INGRESS_ROUTES[$i]}"
                DOMAIN="${ROUTE%%:*}"
                PORT="${ROUTE##*:}"
                echo "  $((i+1)). $DOMAIN -> $APP_NAME:$PORT"
            done
        fi
        
        echo ""
        print_menu "1. Add ingress route"
        print_menu "2. Remove ingress route"
        print_menu "3. Done with ingress configuration"
        echo ""
        print_question "Choose an option:"
        read_input INGRESS_CHOICE
        
        case "$INGRESS_CHOICE" in
            1)
                add_ingress_route
                ;;
            2)
                remove_ingress_route
                ;;
            3)
                break
                ;;
            *)
                print_error "Invalid choice"
                ;;
        esac
    done
}

# Add a single ingress route
add_ingress_route() {
    print_question "Enter domain name (e.g., myapp.winit.dev):"
    read_input DOMAIN
    
    if [ -z "$DOMAIN" ]; then
        print_error "Domain cannot be empty"
        return
    fi
    
    # Check if route already exists
    if grep -q "host: ${DOMAIN}" "$INGRESS_FILE" 2>/dev/null; then
        print_warning "Ingress route for ${DOMAIN} already exists"
        return
    fi
    
    print_question "Enter local port for $DOMAIN [default: $CONTAINER_PORT]:"
    read_input PORT_INPUT
    PORT="${PORT_INPUT:-$CONTAINER_PORT}"
    
    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        print_warning "Invalid port, using container port: $CONTAINER_PORT"
        PORT="$CONTAINER_PORT"
    fi
    
    add_ingress_route_to_file "$DOMAIN" "$PORT"
    CHANGES_MADE=true
    print_success "Added ingress route: ${DOMAIN} -> ${APP_NAME}:${PORT}"
}

# Remove an ingress route
remove_ingress_route() {
    list_ingress_routes
    
    if [ ${#INGRESS_ROUTES[@]} -eq 0 ]; then
        print_warning "No ingress routes to remove"
        return
    fi
    
    echo ""
    print_question "Enter domain name to remove:"
    read_input DOMAIN_TO_REMOVE
    
    if [ -z "$DOMAIN_TO_REMOVE" ]; then
        return
    fi
    
    remove_ingress_route_from_file "$DOMAIN_TO_REMOVE"
    CHANGES_MADE=true
    print_success "Removed ingress route for: $DOMAIN_TO_REMOVE"
}

# Add ingress route to file
add_ingress_route_to_file() {
    DOMAIN="$1"
    PORT="$2"
    
    if [ ! -f "$INGRESS_FILE" ]; then
        print_error "Ingress file not found: $INGRESS_FILE"
        return 1
    fi
    
    # Determine section header based on environment
    if [ "$ENVIRONMENT" = "production" ]; then
        SECTION_HEADER="# Production Namespace Routes"
    else
        SECTION_HEADER="# Staging Namespace Routes"
    fi
    
    # Check if the section exists, if not create it
    if ! grep -q "$SECTION_HEADER" "$INGRESS_FILE"; then
        print_info "Creating ${ENVIRONMENT} namespace section in ingress file..."
        if grep -q "# ArgoCD Namespace Routes" "$INGRESS_FILE"; then
            sed -i "/# ArgoCD Namespace Routes/i\\
---\\
${SECTION_HEADER}\\
apiVersion: networking.k8s.io/v1\\
kind: Ingress\\
metadata:\\
  name: cloudflare-tunnel-routes-${NAMESPACE}\\
  namespace: ${NAMESPACE}\\
  annotations:\\
    cloudflare-tunnel-ingress-controller.strrl.dev/ingress-class: cloudflare-tunnel\\
spec:\\
  ingressClassName: cloudflare-tunnel\\
  rules:\\
" "$INGRESS_FILE"
        else
            cat >> "$INGRESS_FILE" <<EOF

---
${SECTION_HEADER}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: cloudflare-tunnel-routes-${NAMESPACE}
  namespace: ${NAMESPACE}
  annotations:
    cloudflare-tunnel-ingress-controller.strrl.dev/ingress-class: cloudflare-tunnel
spec:
  ingressClassName: cloudflare-tunnel
  rules:
EOF
        fi
    fi
    
    # Insert route before the --- separator after the target section
    TEMP_FILE=$(mktemp)
    awk -v domain="$DOMAIN" -v app="$APP_NAME" -v port="$PORT" -v namespace="$NAMESPACE" -v section_header="$SECTION_HEADER" '
        BEGIN { in_target_section = 0; inserted = 0 }
        index($0, section_header) > 0 { in_target_section = 1 }
        /^---$/ && in_target_section && !inserted {
            print "    # " app ": " domain " -> " app "." namespace ":" port
            print "    - host: " domain
            print "      http:"
            print "        paths:"
            print "          - path: /"
            print "            pathType: Prefix"
            print "            backend:"
            print "              service:"
            print "                name: " app
            print "                port:"
            print "                  number: " port
            print ""
            inserted = 1
            in_target_section = 0
        }
        { print }
    ' "$INGRESS_FILE" > "$TEMP_FILE"
    
    mv "$TEMP_FILE" "$INGRESS_FILE"
}

# Remove ingress route from file
remove_ingress_route_from_file() {
    DOMAIN="$1"
    
    if [ ! -f "$INGRESS_FILE" ]; then
        return 1
    fi
    
    # Find and remove the route block for this domain
    TEMP_FILE=$(mktemp)
    awk -v domain="$DOMAIN" '
        BEGIN { skip_block = 0; in_block = 0 }
        /host: / && index($0, domain) > 0 {
            skip_block = 1
            in_block = 1
            next
        }
        in_block && /^    - host:/ {
            skip_block = 0
            in_block = 0
        }
        in_block && /^---$/ {
            skip_block = 0
            in_block = 0
        }
        in_block && /^    [^ ]/ && !/^    #/ {
            skip_block = 1
        }
        in_block && /^  [^ ]/ {
            skip_block = 0
            in_block = 0
        }
        !skip_block { print }
    ' "$INGRESS_FILE" > "$TEMP_FILE"
    
    mv "$TEMP_FILE" "$INGRESS_FILE"
}

# Create or update Kubernetes manifest
create_or_update_manifest() {
    print_info "Creating/updating Kubernetes manifest..."
    
    mkdir -p "${K8S_DIR}/${APP_NAME}"
    
    # Determine component type based on port
    if [ "$CONTAINER_PORT" = "80" ]; then
        COMPONENT="frontend"
        CONTAINER_NAME="nginx"
    else
        COMPONENT="backend"
        CONTAINER_NAME="app"
    fi
    
    # Health check path
    if [ "$CONTAINER_PORT" = "80" ]; then
        HEALTH_PATH="/health"
        HEALTH_INITIAL_DELAY=10
        HEALTH_PERIOD=10
    else
        HEALTH_PATH="/health"
        HEALTH_INITIAL_DELAY=30
        HEALTH_PERIOD=10
    fi
    
    cat > "$MANIFEST_FILE" <<EOF
# Single-file app definition: ${APP_NAME}
# Auto-generated by setup-app.sh
# Environment: ${ENVIRONMENT}

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    component: ${COMPONENT}
spec:
  replicas: ${REPLICAS}
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
        component: ${COMPONENT}
        fargate: enabled
    spec:
      containers:
      - name: ${CONTAINER_NAME}
        image: ${ECR_REGISTRY}/${APP_NAME}:latest
        imagePullPolicy: Always
        ports:
        - containerPort: ${CONTAINER_PORT}
          name: http
          protocol: TCP
        
        resources:
          requests:
            memory: "${MEMORY_REQUEST}"
            cpu: "${CPU_REQUEST}"
          limits:
            memory: "${MEMORY_LIMIT}"
            cpu: "${CPU_LIMIT}"
        
        # Health checks
        livenessProbe:
          httpGet:
            path: ${HEALTH_PATH}
            port: ${CONTAINER_PORT}
          initialDelaySeconds: ${HEALTH_INITIAL_DELAY}
          periodSeconds: ${HEALTH_PERIOD}
          timeoutSeconds: 5
          failureThreshold: 3
        
        readinessProbe:
          httpGet:
            path: ${HEALTH_PATH}
            port: ${CONTAINER_PORT}
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
      
      # Graceful shutdown
      terminationGracePeriodSeconds: 30

---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
spec:
  type: ClusterIP
  selector:
    app: ${APP_NAME}
  ports:
  - port: ${CONTAINER_PORT}
    targetPort: ${CONTAINER_PORT}
    protocol: TCP
    name: http
EOF
    
    CHANGES_MADE=true
    print_success "Created/updated $MANIFEST_FILE"
}

# Create or update README
create_or_update_readme() {
    README_FILE="${K8S_DIR}/${APP_NAME}/README.md"
    
    list_ingress_routes
    INGRESS_LIST=""
    if [ ${#INGRESS_ROUTES[@]} -gt 0 ]; then
        INGRESS_LIST="\n## Access\n\n"
        for route in "${INGRESS_ROUTES[@]}"; do
            DOMAIN="${route%%:*}"
            INGRESS_LIST="${INGRESS_LIST}- https://${DOMAIN}\n"
        done
    fi
    
    cat > "$README_FILE" <<EOF
# ${APP_NAME}

Kubernetes manifests for ${APP_NAME}.

## Environment

**${ENVIRONMENT^}** (namespace: ${NAMESPACE})

## Deployment

This app is automatically discovered by ArgoCD ApplicationSet.
${INGRESS_LIST}
## Configuration

- Environment: ${ENVIRONMENT}
- Namespace: ${NAMESPACE}
- Replicas: ${REPLICAS}
- Resources:
  - Memory: ${MEMORY_REQUEST} (request) / ${MEMORY_LIMIT} (limit)
  - CPU: ${CPU_REQUEST} (request) / ${CPU_LIMIT} (limit)
- Container Port: ${CONTAINER_PORT}

## Build & Deploy

\`\`\`bash
# Deploy using script
cd ../WinIT-DO
./scripts/deploy-app.sh ${APP_NAME} v1.0.0-${ENVIRONMENT} ${GITHUB_ORG}/${APP_NAME}-main
\`\`\`
EOF
    
    CHANGES_MADE=true
    print_success "Created/updated README"
}

# Create GitHub repository for app source code
create_app_repo() {
    SOURCE_REPO="${GITHUB_ORG}/${APP_NAME}-main"
    
    print_info "Checking for app source repository: $SOURCE_REPO"
    
    if gh repo view "$SOURCE_REPO" &> /dev/null; then
        print_success "Repository already exists: $SOURCE_REPO"
        return 0
    fi
    
    print_question "Create new GitHub repository '$SOURCE_REPO' for app source code? (Y/n):"
    read_input CREATE_REPO
    
    if [[ "$CREATE_REPO" =~ ^[Nn]$ ]]; then
        print_info "Skipping repository creation"
        return 0
    fi
    
    print_info "Creating repository: $SOURCE_REPO"
    
    if gh repo create "$SOURCE_REPO" --private --description "Source code for ${APP_NAME}" 2>&1; then
        print_success "Created repository: $SOURCE_REPO"
        
        # Initialize repository with basic files
        print_info "Initializing repository with basic structure..."
        
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"
        
        git init -b main
        
        # Set git config (use existing if available, otherwise set defaults)
        if ! git config user.name &> /dev/null; then
            git config user.name "GitHub Actions"
        fi
        if ! git config user.email &> /dev/null; then
            git config user.email "actions@github.com"
        fi
        
        # Create basic README
        cat > README.md <<EOF
# ${APP_NAME}

Source code for ${APP_NAME} application.

## Deployment

This app is deployed via ArgoCD from the k8s-production repository.

## Local Development

\`\`\`bash
# Install dependencies
npm install  # or pip install, etc.

# Run locally
npm start    # or python app.py, etc.
\`\`\`

## Build & Deploy

See k8s-production repository for deployment configuration.
EOF
        
        # Create .gitignore
        cat > .gitignore <<EOF
# Dependencies
node_modules/
__pycache__/
*.pyc
venv/
env/

# Build outputs
dist/
build/
*.log

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db
EOF
        
        git add README.md .gitignore
        git commit -m "Initial commit: ${APP_NAME}"
        git remote add origin "https://github.com/${SOURCE_REPO}.git"
        git push -u origin main
        
        cd - > /dev/null
        rm -rf "$TEMP_DIR"
        
        print_success "Repository initialized and pushed to GitHub"
        print_info "Repository URL: https://github.com/${SOURCE_REPO}"
    else
        print_error "Failed to create repository"
        print_info "You can create it manually:"
        echo "  gh repo create $SOURCE_REPO --private"
        return 1
    fi
}

# Commit and push changes
commit_and_push() {
    if [ "$CHANGES_MADE" = false ]; then
        print_info "No changes to commit"
        # Still offer to create app repo if it's a new app
        if [ "$APP_EXISTS" = false ]; then
            create_app_repo
        fi
        return 0
    fi
    
    cd k8s-production
    
    # Check if there are changes
    if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        print_info "Committing changes..."
        
        git add "${APP_NAME}/" 2>/dev/null || true
        git add "apps/tunnel-ingress/tunnel-ingress.yaml" 2>/dev/null || true
        
        COMMIT_MSG="Configure ${APP_NAME} app"
        if [ "$APP_EXISTS" = true ]; then
            COMMIT_MSG="Update ${APP_NAME} app configuration"
        fi
        
        git commit -m "$COMMIT_MSG" || {
            print_warning "Nothing to commit (no changes detected)"
            cd ..
            # Still offer to create app repo if it's a new app
            if [ "$APP_EXISTS" = false ]; then
                create_app_repo
            fi
            return 0
        }
        
        print_info "Pushing to GitHub..."
        git push origin main 2>/dev/null || git push origin master 2>/dev/null || {
            print_error "Failed to push changes"
            print_info "You can push manually:"
            echo "  cd k8s-production"
            echo "  git push origin main"
            cd ..
            return 1
        }
        
        print_success "Changes pushed to GitHub"
    else
        print_info "No changes detected"
    fi
    
    cd ..
    
    # Create app source repository if it's a new app
    if [ "$APP_EXISTS" = false ]; then
        create_app_repo
    fi
}

# Main menu
main_menu() {
    while true; do
        echo ""
        echo "============================================================================"
        if [ "$APP_EXISTS" = true ]; then
            echo "Edit App: $APP_NAME"
        else
            echo "Configure New App: $APP_NAME"
        fi
        echo "============================================================================"
        echo ""
        print_menu "1. Configure app settings (replicas, resources, port)"
        print_menu "2. Manage ingress routes"
        print_menu "3. Save and push changes to GitHub"
        print_menu "4. Exit without saving"
        echo ""
        print_question "Choose an option:"
        read_input MENU_CHOICE
        
        case "$MENU_CHOICE" in
            1)
                prompt_environment
                prompt_replicas
                prompt_resources
                prompt_container_port
                create_or_update_manifest
                create_or_update_readme
                ;;
            2)
                manage_ingress_menu
                create_or_update_readme
                ;;
            3)
                commit_and_push
                echo ""
                print_success "Configuration complete!"
                break
                ;;
            4)
                print_info "Exiting without saving changes"
                exit 0
                ;;
            *)
                print_error "Invalid choice"
                ;;
        esac
    done
}

# Main function
main() {
    echo "============================================================================"
    echo "🚀 App Configuration Script"
    echo "============================================================================"
    echo ""
    
    # Check if we can read from terminal (for interactive input)
    # This is a pre-check, but read_input() will handle the actual reading
    if [ ! -t 0 ] && [ ! -e /dev/tty ]; then
        print_warning "Terminal device (/dev/tty) not found. Interactive input may not work."
        echo ""
        echo "For best results, download and run the script:"
        echo "  curl -fsSL https://raw.githubusercontent.com/winit-testabc/app-manager-script/main/setup-app.sh -o setup-app.sh"
        echo "  chmod +x setup-app.sh"
        echo "  ./setup-app.sh"
        echo ""
        echo "Continuing anyway..."
    fi
    
    # Check prerequisites
    check_gh_cli
    
    # Setup k8s-production repository
    setup_k8s_repo
    
    # Get app name
    prompt_app_name
    
    # Show main menu
    main_menu
}

# Run main function
main "$@"
