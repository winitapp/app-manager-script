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
ECR_REGISTRY="418295680544.dkr.ecr.us-east-1.amazonaws.com/winitxyz"

# Global variables
APP_NAME=""
ENVIRONMENT=""
NAMESPACE=""
K8S_REPO=""
K8S_DIR=""
INGRESS_FILE=""
K8S_TEMP_DIR=""
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

# Set k8s repo based on environment
set_k8s_repo() {
    if [ "$ENVIRONMENT" = "staging" ]; then
        K8S_REPO="${GITHUB_ORG}/k8s-staging"
        K8S_DIR_NAME="k8s-staging"
    else
        K8S_REPO="${GITHUB_ORG}/k8s-production"
        K8S_DIR_NAME="k8s-production"
    fi
    
    # Create temp directory for k8s repo
    K8S_TEMP_DIR=$(mktemp -d)
    K8S_DIR="${K8S_TEMP_DIR}/${K8S_DIR_NAME}/apps"
    INGRESS_FILE="${K8S_TEMP_DIR}/${K8S_DIR_NAME}/apps/tunnel-ingress/tunnel-ingress.yaml"
}

# Clone k8s repository to temp directory
setup_k8s_repo() {
    print_info "Cloning ${K8S_DIR_NAME} repository to temporary directory..."
    
    if gh repo view "$K8S_REPO" &> /dev/null; then
        if gh repo clone "$K8S_REPO" "$K8S_TEMP_DIR/${K8S_DIR_NAME}" 2>&1; then
            print_success "Cloned ${K8S_DIR_NAME} repository"
        else
            print_error "Failed to clone ${K8S_DIR_NAME} repository"
            echo ""
            echo "You can clone it manually:"
            echo "  gh repo clone $K8S_REPO"
            rm -rf "$K8S_TEMP_DIR"
            exit 1
        fi
    else
        print_error "Repository $K8S_REPO not found or not accessible"
        rm -rf "$K8S_TEMP_DIR"
        exit 1
    fi
}

# Cleanup temp directory
cleanup_k8s_repo() {
    if [ -n "$K8S_TEMP_DIR" ] && [ -d "$K8S_TEMP_DIR" ]; then
        print_info "Cleaning up temporary directory..."
        rm -rf "$K8S_TEMP_DIR"
    fi
}

# Check if app exists
check_app_exists() {
    MANIFEST_FILE="${K8S_DIR}/${APP_NAME}/${APP_NAME}.yaml"
    if [ -f "$MANIFEST_FILE" ]; then
        APP_EXISTS=true
        # Extract current values from manifest
        extract_current_values
        print_success "App '$APP_NAME' found (existing app)"
        echo ""
        echo "Current configuration:"
        echo "  Environment: $ENVIRONMENT (namespace: $NAMESPACE)"
        echo "  Replicas: $REPLICAS"
        echo "  Container Port: $CONTAINER_PORT"
        echo "  Resources: ${MEMORY_REQUEST}/${MEMORY_LIMIT} memory, ${CPU_REQUEST}/${CPU_LIMIT} CPU"
        echo ""
        return 0
    else
        print_info "App '$APP_NAME' not found (new app)"
        return 1
    fi
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
    awk -v domain="$DOMAIN" -v app="$APP_NAME" -v port="$PORT" -v ns="$NAMESPACE" -v section_header="$SECTION_HEADER" '
        BEGIN { in_target_section = 0; inserted = 0 }
        index($0, section_header) > 0 { in_target_section = 1 }
        /^---$/ && in_target_section && !inserted {
            print "    # " app ": " domain " -> " app "." ns ":" port
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
./scripts/deploy-app.sh ${APP_NAME} v1.0.0-${ENVIRONMENT} ${GITHUB_ORG}/${APP_NAME}
\`\`\`
EOF
    
    CHANGES_MADE=true
    print_success "Created/updated README"
}

# Create GitHub repository for app source code
create_app_repo() {
    SOURCE_REPO="${GITHUB_ORG}/${APP_NAME}"
    
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

This app is deployed via ArgoCD from the ${K8S_DIR_NAME} repository.

## Local Development

\`\`\`bash
# Install dependencies
npm install  # or pip install, etc.

# Run locally
npm start    # or python app.py, etc.
\`\`\`

## Build & Deploy

See ${K8S_DIR_NAME} repository for deployment configuration.
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
        
        # Create deploy.sh script
        cat > deploy.sh <<DEPLOY_EOF
#!/bin/bash

# ============================================================================
# Deploy Script for ${APP_NAME}
# ============================================================================
# This script helps you deploy ${APP_NAME} by prompting for version and environment.
# It calls the deployment workflow in the k8s repository.
#
# Usage:
#   ./deploy.sh
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
APP_NAME="${APP_NAME}"
SOURCE_REPO="${GITHUB_ORG}/${APP_NAME}"
GITHUB_ORG="${GITHUB_ORG}"

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
    
    if [ -t 0 ]; then
        read -r -p "$prompt_text" "$var_name"
    elif [ -e "$input_source" ] && [ -r "$input_source" ]; then
        read -r -p "$prompt_text" "$var_name" < "$input_source"
    else
        print_error "Cannot read from terminal. Please run the script directly."
        exit 1
    fi
    
    if [ -z "${!var_name}" ] && [ -n "$default_value" ]; then
        eval "$var_name=\"$default_value\""
    fi
}

# Prompt for environment
prompt_environment() {
    while true; do
        print_question "Select environment (production/staging) [default: production]: "
        read_input "Select environment (production/staging) [default: production]: " ENV "production"
        
        ENV=$(echo "$ENV" | tr '[:upper:]' '[:lower:]')
        
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

# Prompt for version
prompt_version() {
    print_question "Enter version number (e.g., 1.0.0) [default: 1.0.0]: "
    read_input "Enter version number (e.g., 1.0.0) [default: 1.0.0]: " VERSION "1.0.0"
    
    # Remove 'v' prefix if present
    VERSION=$(echo "$VERSION" | sed 's/^v//')
    
    # Validate version format (basic check)
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        print_error "Invalid version format. Expected format: X.Y.Z (e.g., 1.0.0)"
        exit 1
    fi
    
    TAG="v${VERSION}-${ENV_SUFFIX}"
}

# Main execution
main() {
    echo ""
    echo "============================================================================="
    echo "🚀 Deploy ${APP_NAME}"
    echo "============================================================================="
    echo ""
    
    prompt_environment
    prompt_version
    
    echo ""
    print_info "Deployment details:"
    echo "  App: ${APP_NAME}"
    echo "  Version: ${TAG}"
    echo "  Environment: ${ENV_SUFFIX}"
    echo "  Source Repo: ${SOURCE_REPO}"
    echo ""
    
    # Find WinIT-DO directory (assumes app repo is cloned alongside WinIT-DO)
    SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
    
    # Try common locations for WinIT-DO
    WINIT_DO_DIRS=(
        "\$(dirname "\$SCRIPT_DIR")/WinIT-DO"
        "\$(dirname "\$(dirname "\$SCRIPT_DIR")")/WinIT-DO"
        "\$HOME/WinIT-DO"
        "."
    )
    
    DEPLOY_SCRIPT=""
    for dir in "\${WINIT_DO_DIRS[@]}"; do
        if [ -f "\$dir/scripts/deploy-app.sh" ]; then
            DEPLOY_SCRIPT="\$dir/scripts/deploy-app.sh"
            break
        fi
    done
    
    if [ -z "\$DEPLOY_SCRIPT" ] || [ ! -f "\$DEPLOY_SCRIPT" ]; then
        print_error "Could not find deploy-app.sh script"
        print_info ""
        print_info "Please ensure WinIT-DO repository is cloned and accessible."
        print_info ""
        print_info "You can deploy manually using:"
        echo "  cd WinIT-DO"
        echo "  ./scripts/deploy-app.sh ${APP_NAME} \${TAG} ${SOURCE_REPO}"
        exit 1
    fi
    
    print_info "Running deployment script..."
    echo ""
    
    # Execute deploy script
    bash "\$DEPLOY_SCRIPT" "${APP_NAME}" "\${TAG}" "${SOURCE_REPO}"
}

main "\$@"
DEPLOY_EOF
        
        chmod +x deploy.sh
        
        git add README.md .gitignore deploy.sh
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
    cd "${K8S_TEMP_DIR}/${K8S_DIR_NAME}"
    
    # Always check for changes, regardless of CHANGES_MADE flag
    # Add all modified files
    FILES_TO_ADD=()
    
    # Add app directory and YAML file if they exist
    if [ -d "apps/${APP_NAME}" ]; then
        # Always add the app directory (git add will handle what's changed)
        # This ensures YAML files, README, and any other files are included
        FILES_TO_ADD+=("apps/${APP_NAME}/")
    fi
    
    # Explicitly add the YAML file if it exists (even if directory was already added)
    if [ -f "apps/${APP_NAME}/${APP_NAME}.yaml" ]; then
        # Check if it's modified or untracked
        if ! git diff --quiet "apps/${APP_NAME}/${APP_NAME}.yaml" 2>/dev/null || [ -z "$(git ls-files "apps/${APP_NAME}/${APP_NAME}.yaml" 2>/dev/null)" ]; then
            FILES_TO_ADD+=("apps/${APP_NAME}/${APP_NAME}.yaml")
        fi
    fi
    
    # Also add README if it exists
    if [ -f "apps/${APP_NAME}/README.md" ]; then
        if ! git diff --quiet "apps/${APP_NAME}/README.md" 2>/dev/null || [ -z "$(git ls-files "apps/${APP_NAME}/README.md" 2>/dev/null)" ]; then
            FILES_TO_ADD+=("apps/${APP_NAME}/README.md")
        fi
    fi
    
    # Add ingress file if it exists and has changes
    if [ -f "apps/tunnel-ingress/tunnel-ingress.yaml" ]; then
        if git diff --quiet "apps/tunnel-ingress/tunnel-ingress.yaml" 2>/dev/null; then
            # No changes in ingress file
            :
        else
            FILES_TO_ADD+=("apps/tunnel-ingress/tunnel-ingress.yaml")
        fi
    fi
    
    # Check if there are any changes to commit
    if [ ${#FILES_TO_ADD[@]} -eq 0 ]; then
        # Check if there are any unstaged changes at all
        if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
            print_info "No changes to commit"
            cd - > /dev/null
            # Still offer to create app repo if it's a new app
            if [ "$APP_EXISTS" = false ]; then
                create_app_repo
            fi
            cleanup_k8s_repo
            return 0
        fi
    fi
    
    # Add files
    print_info "Staging changes..."
    for file in "${FILES_TO_ADD[@]}"; do
        if git add "$file" 2>/dev/null; then
            print_info "  Added: $file"
        else
            print_warning "  Could not add: $file (may not exist or already staged)"
        fi
    done
    
    # Also add any other modified files in the apps directory
    git add -u apps/ 2>/dev/null || true
    
    # Check if there's anything to commit
    if git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
        print_warning "No changes staged for commit"
        cd - > /dev/null
        # Still offer to create app repo if it's a new app
        if [ "$APP_EXISTS" = false ]; then
            create_app_repo
        fi
        cleanup_k8s_repo
        return 0
    fi
    
    # Commit changes
    COMMIT_MSG="Configure ${APP_NAME} app"
    if [ "$APP_EXISTS" = true ]; then
        COMMIT_MSG="Update ${APP_NAME} app configuration"
    fi
    
    print_info "Committing changes..."
    git commit -m "$COMMIT_MSG" || {
        print_error "Failed to commit changes"
        cd - > /dev/null
        cleanup_k8s_repo
        return 1
    }
    
    print_info "Pushing to GitHub..."
    git push origin main 2>/dev/null || git push origin master 2>/dev/null || {
        print_error "Failed to push changes"
        print_info "You can push manually:"
        echo "  cd ${K8S_TEMP_DIR}/${K8S_DIR_NAME}"
        echo "  git push origin main"
        cd - > /dev/null
        cleanup_k8s_repo
        return 1
    }
    
    print_success "Changes committed and pushed to GitHub"
    
    cd - > /dev/null
    
    # Cleanup temp directory
    cleanup_k8s_repo
    
    # Create app source repository if it's a new app
    if [ "$APP_EXISTS" = false ]; then
        create_app_repo
    fi
}

# Write deploy.sh script to local filesystem
write_deploy_script() {
    local deploy_script_path="${APP_NAME}-deploy.sh"
    
    print_info "Writing deploy.sh script to: ${deploy_script_path}"
    
    cat > "$deploy_script_path" <<DEPLOY_EOF
#!/bin/bash

# ============================================================================
# Deploy Script for ${APP_NAME}
# ============================================================================
# This script helps you deploy ${APP_NAME} by prompting for version and environment.
# It calls the deployment workflow in the k8s repository.
#
# Usage:
#   ./${deploy_script_path}
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
APP_NAME="${APP_NAME}"
SOURCE_REPO="${GITHUB_ORG}/${APP_NAME}"
GITHUB_ORG="${GITHUB_ORG}"

# Function to print colored output
print_info() {
    echo -e "\${BLUE}ℹ\${NC} \$1"
}

print_success() {
    echo -e "\${GREEN}✅\${NC} \$1"
}

print_warning() {
    echo -e "\${YELLOW}⚠️\${NC} \$1"
}

print_error() {
    echo -e "\${RED}❌\${NC} \$1"
}

print_question() {
    echo -e "\${YELLOW}?\${NC} \$1"
}

# Function to read input (handles piped input)
read_input() {
    local prompt_text="\$1"
    local var_name="\$2"
    local default_value="\$3"
    local input_source="/dev/tty"
    local user_input=""
    
    if [ -t 0 ]; then
        read -r -p "\$prompt_text" user_input
    elif [ -e "\$input_source" ] && [ -r "\$input_source" ]; then
        read -r -p "\$prompt_text" user_input < "\$input_source"
    else
        print_error "Cannot read from terminal. Please run the script directly."
        exit 1
    fi
    
    # Use default if input is empty
    if [ -z "\$user_input" ] && [ -n "\$default_value" ]; then
        user_input="\$default_value"
    fi
    
    # Set the variable using eval (safe because we control the var_name)
    eval "\$var_name=\"\$user_input\""
}

# Prompt for environment
prompt_environment() {
    while true; do
        print_question "Select environment (production/staging) [default: production]: "
        read_input "Select environment (production/staging) [default: production]: " ENV_INPUT "production"
        
        ENV=\$(echo "\$ENV_INPUT" | tr '[:upper:]' '[:lower:]')
        
        if [ "\$ENV" = "production" ] || [ "\$ENV" = "prod" ]; then
            ENV_SUFFIX="prod"
            break
        elif [ "\$ENV" = "staging" ] || [ "\$ENV" = "stage" ]; then
            ENV_SUFFIX="staging"
            break
        else
            print_error "Invalid environment. Please enter 'production' or 'staging'."
        fi
    done
}

# Get latest version tag from k8s repository
get_latest_version() {
    local env_suffix="\${ENV_SUFFIX}"
    local app_name="${APP_NAME}"
    
    # Determine k8s repo based on environment
    if [ "\$env_suffix" = "staging" ]; then
        local k8s_repo="\${GITHUB_ORG}/k8s-staging"
    else
        local k8s_repo="\${GITHUB_ORG}/k8s-production"
    fi
    
    # Get all tags matching the pattern v*.*.*-{app_name}-{env}
    # Format: v1.0.0-test3-prod or v1.0.0-test3-staging
    local latest_tag=\$(gh api repos/\${k8s_repo}/git/refs/tags --jq '.[].ref' 2>/dev/null | \\
        grep -E "refs/tags/v[0-9]+\\.[0-9]+\\.[0-9]+-\${app_name}-\${env_suffix}\$" | \\
        sed "s|refs/tags/v||" | sed "s/-\${app_name}-\${env_suffix}\$//" | \\
        sort -V | tail -1)
    
    if [ -z "\$latest_tag" ]; then
        echo "1.0.0"
    else
        echo "\$latest_tag"
    fi
}

# Increment version (patch version)
increment_version() {
    local version="\$1"
    local major=\$(echo "\$version" | cut -d. -f1)
    local minor=\$(echo "\$version" | cut -d. -f2)
    local patch=\$(echo "\$version" | cut -d. -f3)
    
    patch=\$((patch + 1))
    echo "\${major}.\${minor}.\${patch}"
}

# Check for pending changes and ask to commit
check_pending_changes() {
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        return 0
    fi
    
    # Check for uncommitted changes
    if [ -n "\$(git status --porcelain)" ]; then
        echo ""
        print_warning "You have uncommitted changes:"
        git status --short
        echo ""
        print_question "Do you want to commit these changes before deploying? (Y/n): "
        read_input "Do you want to commit these changes before deploying? (Y/n): " COMMIT_CHANGES "Y"
        
        if [[ "\$COMMIT_CHANGES" =~ ^[Yy]?\$ ]]; then
            print_question "Enter commit message [default: WIP: prepare for deployment]: "
            read_input "Enter commit message [default: WIP: prepare for deployment]: " COMMIT_MSG "WIP: prepare for deployment"
            
            git add -A
            git commit -m "\$COMMIT_MSG" || {
                print_error "Failed to commit changes"
                exit 1
            }
            
            print_question "Do you want to push these changes? (Y/n): "
            read_input "Do you want to push these changes? (Y/n): " PUSH_CHANGES "Y"
            
            if [[ "\$PUSH_CHANGES" =~ ^[Yy]?\$ ]]; then
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
    local latest_version=\$(get_latest_version)
    local suggested_version=\$(increment_version "\$latest_version")
    
    print_info "Latest version for \${ENV_SUFFIX}: v\${latest_version}"
    print_question "Enter version number [default: \${suggested_version}]: "
    read_input "Enter version number [default: \${suggested_version}]: " VERSION_INPUT "\$suggested_version"
    
    # Remove 'v' prefix if present
    VERSION=\$(echo "\$VERSION_INPUT" | sed 's/^v//')
    
    # Validate version format (basic check)
    if [[ ! "\$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        print_error "Invalid version format. Expected format: X.Y.Z (e.g., 1.0.0)"
        exit 1
    fi
    
    TAG="v\${VERSION}-\${ENV_SUFFIX}"
}

# Monitor deployment workflow
monitor_deployment() {
    local env_suffix="\${ENV_SUFFIX}"
    local app_name="${APP_NAME}"
    
    # Determine k8s repo based on environment
    if [ "\$env_suffix" = "staging" ]; then
        local k8s_repo="\${GITHUB_ORG}/k8s-staging"
    else
        local k8s_repo="\${GITHUB_ORG}/k8s-production"
    fi
    
    local workflow_file="deploy-from-tag.yml"
    
    print_info "Monitoring deployment workflow..."
    print_info "Repository: \$k8s_repo"
    print_info "Workflow: \$workflow_file"
    echo ""
    
    # Wait a moment for the workflow to start
    sleep 3
    
    # Get the latest workflow run (most recent one)
    local run_id=\$(gh run list --repo "\$k8s_repo" --workflow "\$workflow_file" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null)
    
    if [ -z "\$run_id" ] || [ "\$run_id" = "null" ]; then
        print_warning "Could not find workflow run. You can monitor manually:"
        echo "  gh run list --repo \$k8s_repo --workflow \$workflow_file"
        echo ""
        echo "Or view actions at:"
        echo "  https://github.com/\$k8s_repo/actions"
        return 0
    fi
    
    local run_url="https://github.com/\$k8s_repo/actions/runs/\$run_id"
    print_info "Workflow run URL: \$run_url"
    print_info "Watching workflow run #\${run_id}"
    echo ""
    
    # Watch the workflow run
    gh run watch "\$run_id" --repo "\$k8s_repo" --exit-status
    
    local exit_code=\$?
    echo ""
    if [ \$exit_code -eq 0 ]; then
        print_success "Deployment completed successfully!"
        echo ""
        print_info "View workflow run: \$run_url"
    else
        print_error "Deployment failed with exit code \$exit_code"
        echo ""
        print_info "View workflow run: \$run_url"
        exit \$exit_code
    fi
}

# Main execution
main() {
    echo ""
    echo "============================================================================="
    echo "🚀 Deploy ${APP_NAME}"
    echo "============================================================================="
    echo ""
    
    # Check for pending changes
    check_pending_changes
    
    prompt_environment
    prompt_version
    
    echo ""
    print_info "Deployment details:"
    echo "  App: ${APP_NAME}"
    echo "  Version: \${TAG}"
    echo "  Environment: \${ENV_SUFFIX}"
    echo "  Source Repo: ${SOURCE_REPO}"
    echo ""
    
    # Find WinIT-DO directory (assumes app repo is cloned alongside WinIT-DO)
    SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
    
    # Try common locations for WinIT-DO
    WINIT_DO_DIRS=(
        "\$(dirname "\$SCRIPT_DIR")/WinIT-DO"
        "\$(dirname "\$(dirname "\$SCRIPT_DIR")")/WinIT-DO"
        "\$HOME/WinIT-DO"
        "."
    )
    
    DEPLOY_SCRIPT=""
    for dir in "\${WINIT_DO_DIRS[@]}"; do
        if [ -f "\$dir/scripts/deploy-app.sh" ]; then
            DEPLOY_SCRIPT="\$dir/scripts/deploy-app.sh"
            break
        fi
    done
    
    if [ -z "\$DEPLOY_SCRIPT" ] || [ ! -f "\$DEPLOY_SCRIPT" ]; then
        print_error "Could not find deploy-app.sh script"
        print_info ""
        print_info "Please ensure WinIT-DO repository is cloned and accessible."
        print_info ""
        print_info "You can deploy manually using:"
        echo "  cd WinIT-DO"
        echo "  ./scripts/deploy-app.sh ${APP_NAME} \${TAG} ${SOURCE_REPO}"
        exit 1
    fi
    
    print_info "Running deployment script..."
    echo ""
    
    # Execute deploy script in background and capture output
    bash "\$DEPLOY_SCRIPT" "${APP_NAME}" "\${TAG}" "${SOURCE_REPO}" &
    local deploy_pid=\$!
    
    # Wait a moment for the workflow to be triggered
    sleep 3
    
    # Monitor the deployment
    monitor_deployment
}

main "\$@"
DEPLOY_EOF
    
    # Make the script executable
    chmod +x "$deploy_script_path"
    
    if [ -x "$deploy_script_path" ]; then
        print_success "Created deploy script: ${deploy_script_path}"
    else
        print_warning "Created deploy script but failed to set execute permissions: ${deploy_script_path}"
        print_info "You may need to run: chmod +x ${deploy_script_path}"
    fi
}

# Show current configuration in table format
show_current_config() {
    echo ""
    echo "============================================================================="
    echo "📊 Current Configuration for: $APP_NAME"
    echo "============================================================================="
    echo ""
    
    # Check if app exists
    MANIFEST_FILE="${K8S_DIR}/${APP_NAME}/${APP_NAME}.yaml"
    if [ ! -f "$MANIFEST_FILE" ]; then
        print_warning "App manifest not found. This is a new app."
        echo ""
        echo "┌─────────────────────────────────────────────────────────────────┐"
        echo "│ Status: Not configured yet                                       │"
        echo "└─────────────────────────────────────────────────────────────────┘"
        return
    fi
    
    # Extract values if not already extracted
    if [ -z "$REPLICAS" ]; then
        extract_current_values
    fi
    
    # Check if source repo exists
    SOURCE_REPO="${GITHUB_ORG}/${APP_NAME}"
    REPO_EXISTS=false
    if gh repo view "$SOURCE_REPO" &> /dev/null; then
        REPO_EXISTS=true
    fi
    
    # Get ingress routes
    list_ingress_routes
    
    # Print table
    printf "┌─────────────────────────────────────────────────────────────────┐\n"
    printf "│ %-63s │\n" "Configuration"
    printf "├─────────────────────────────────────────────────────────────────┤\n"
    printf "│ %-25s │ %-36s │\n" "App Name" "$APP_NAME"
    printf "│ %-25s │ %-36s │\n" "Environment" "${ENVIRONMENT:-Not set}"
    printf "│ %-25s │ %-36s │\n" "Namespace" "${NAMESPACE:-Not set}"
    printf "│ %-25s │ %-36s │\n" "Replicas" "${REPLICAS:-Not set}"
    printf "│ %-25s │ %-36s │\n" "Container Port" "${CONTAINER_PORT:-Not set}"
    printf "├─────────────────────────────────────────────────────────────────┤\n"
    printf "│ %-63s │\n" "Resources"
    printf "├─────────────────────────────────────────────────────────────────┤\n"
    printf "│ %-25s │ %-36s │\n" "Memory Request" "${MEMORY_REQUEST:-Not set}"
    printf "│ %-25s │ %-36s │\n" "Memory Limit" "${MEMORY_LIMIT:-Not set}"
    printf "│ %-25s │ %-36s │\n" "CPU Request" "${CPU_REQUEST:-Not set}"
    printf "│ %-25s │ %-36s │\n" "CPU Limit" "${CPU_LIMIT:-Not set}"
    printf "├─────────────────────────────────────────────────────────────────┤\n"
    printf "│ %-63s │\n" "Repository"
    printf "├─────────────────────────────────────────────────────────────────┤\n"
    if [ "$REPO_EXISTS" = true ]; then
        printf "│ %-25s │ %-36s │\n" "Source Repo" "✅ $SOURCE_REPO"
    else
        printf "│ %-25s │ %-36s │\n" "Source Repo" "❌ Not created"
    fi
    printf "│ %-25s │ %-36s │\n" "K8s Repo" "$K8S_REPO"
    printf "│ %-25s │ %-36s │\n" "Manifest Path" "apps/${APP_NAME}/${APP_NAME}.yaml"
    printf "├─────────────────────────────────────────────────────────────────┤\n"
    printf "│ %-63s │\n" "Ingress Routes"
    printf "├─────────────────────────────────────────────────────────────────┤\n"
    if [ ${#INGRESS_ROUTES[@]} -eq 0 ]; then
        printf "│ %-63s │\n" "No ingress routes configured"
    else
        for route in "${INGRESS_ROUTES[@]}"; do
            DOMAIN="${route%%:*}"
            PORT="${route##*:}"
            printf "│ %-25s │ %-36s │\n" "Domain" "$DOMAIN"
            printf "│ %-25s │ %-36s │\n" "  → Port" "$APP_NAME:$PORT"
        done
    fi
    printf "└─────────────────────────────────────────────────────────────────┘\n"
    echo ""
}

# Show usage information
show_usage_info() {
    echo ""
    echo "============================================================================="
    echo "📚 Usage Information"
    echo "============================================================================="
    echo ""
    echo "Your app '${APP_NAME}' has been configured!"
    echo ""
    echo "📦 App Repository:"
    echo "   https://github.com/${GITHUB_ORG}/${APP_NAME}"
    echo ""
    echo "🚀 To deploy your app:"
    echo ""
    echo "   Option 1: Use the deploy.sh script (recommended)"
    echo "   ------------------------------------------------"
    echo "   ./${APP_NAME}-deploy.sh"
    echo ""
    echo "   This will prompt you for:"
    echo "   - Environment (production/staging)"
    echo "   - Version number (e.g., 1.0.0)"
    echo ""
    echo "   Option 2: Use the deploy script directly"
    echo "   ----------------------------------------"
    echo "   cd WinIT-DO"
    echo "   ./scripts/deploy-app.sh ${APP_NAME} v1.0.0-production ${GITHUB_ORG}/${APP_NAME}"
    echo ""
    echo "📝 Kubernetes Manifests:"
    echo "   https://github.com/${K8S_REPO}/tree/main/apps/${APP_NAME}"
    echo ""
    echo "🔍 Monitor deployment:"
    echo "   gh run list --repo ${K8S_REPO} --workflow=deploy-from-tag.yml"
    echo ""
    echo "============================================================================="
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
        print_menu "3. View current configuration"
        print_menu "4. Get deploy script"
        print_menu "5. Save and push changes to GitHub"
        print_menu "6. Exit without saving"
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
                show_current_config
                echo ""
                print_question "Press Enter to continue..."
                read_input DUMMY
                ;;
            4)
                write_deploy_script
                echo ""
                print_question "Press Enter to continue..."
                read_input DUMMY
                ;;
            5)
                commit_and_push
                echo ""
                print_success "Configuration complete!"
                write_deploy_script
                show_usage_info
                break
                ;;
            6)
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
    
    # Get app name first
    prompt_app_name
    
    # Prompt for environment (needed to determine which k8s repo to use)
    prompt_environment
    
    # Set k8s repo based on environment
    set_k8s_repo
    
    # Setup k8s repository
    setup_k8s_repo
    
    # Check if app exists and show main menu
    check_app_exists
    main_menu
}

# Run main function
main "$@"
