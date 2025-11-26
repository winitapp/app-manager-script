# App Manager Script

Interactive script to configure new apps or edit existing ones. This script helps you manage Kubernetes app configurations, ingress routes, and automatically commits and pushes changes to GitHub.

## Repository

**GitHub**: https://github.com/winit-testabc/app-manager-script

## Features

- ✅ **Edit existing apps** - Modify replicas, resources, ports, ingress routes
- ✅ **Create new apps** - Set up complete Kubernetes manifests
- ✅ **Create app repositories** - Automatically creates GitHub repo for app source code
- ✅ **Ingress management** - Add, remove, or edit ingress routes interactively
- ✅ **Auto-commit & push** - Automatically commits and pushes changes to GitHub
- ✅ **Menu-driven interface** - Easy-to-use menu system
- ✅ **Environment support** - Configure for production or staging
- ✅ **Validates inputs** - Provides sensible defaults and validation

## Prerequisites

- **GitHub CLI (`gh`)** installed and authenticated
- Access to the `winit-testabc` GitHub organization
- Write access to the `k8s-production` repository

**Note**: The script will automatically clone the `k8s-production` repository if it doesn't exist locally. You don't need to have it cloned beforehand.

### Quick Setup

```bash
# Install GitHub CLI (if not installed)
# macOS: brew install gh
# Linux: apt install gh  # or yum install gh
# Windows: winget install GitHub.cli

# Authenticate (one-time)
gh auth login
```

## Quick Install & Run

### One-Liner (All Platforms)

**Linux/macOS/Git Bash (Windows):**
```bash
curl -fsSL https://raw.githubusercontent.com/winit-testabc/app-manager-script/main/setup-app.sh | bash -s -- [app-name]
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/winit-testabc/app-manager-script/main/setup-app.sh | bash -s -- [app-name]
```

**Windows (CMD - requires Git Bash or WSL):**
```cmd
curl -fsSL https://raw.githubusercontent.com/winit-testabc/app-manager-script/main/setup-app.sh | bash -s -- [app-name]
```

### Prerequisites

The script requires **GitHub CLI (`gh`)** to be installed and authenticated:

**macOS:**
```bash
brew install gh
gh auth login
```

**Linux (Debian/Ubuntu):**
```bash
sudo apt install gh
gh auth login
```

**Linux (RHEL/CentOS/Fedora):**
```bash
sudo yum install gh  # or sudo dnf install gh
gh auth login
```

**Windows:**
```powershell
winget install GitHub.cli
gh auth login
```

### Alternative: Clone and Run

```bash
git clone https://github.com/winit-testabc/app-manager-script.git
cd app-manager-script
./setup-app.sh [app-name]
```

## Usage

Run the setup script:
```bash
./setup-app.sh [app-name]
```

If you provide an app name, it will edit that app if it exists, or create a new one.

3. Use the interactive menu:
   - **Option 1**: Configure app settings (replicas, resources, port, environment)
   - **Option 2**: Manage ingress routes (add/remove domains)
   - **Option 3**: Save and push changes to GitHub
   - **Option 4**: Exit without saving

### Editing Existing Apps

When editing an existing app, the script will:
- Show current configuration values
- Allow you to press Enter to keep existing values
- Only update what you change

### Managing Ingress Routes

The ingress management menu allows you to:
- **Add routes**: Configure new domain-to-port mappings
- **Remove routes**: Delete existing ingress routes
- Routes are automatically added to the correct namespace section (production/staging)

## What It Does

### 1. Clones k8s-production Repository
- Automatically clones `winit-testabc/k8s-production` if it doesn't exist locally
- Updates it if it already exists
- Uses GitHub CLI (`gh`) for all repository operations

### 2. Detects Existing Apps
- Checks if app already exists
- Shows current configuration when editing
- Allows incremental updates (only change what you want)

### 2a. Creates App Source Repository (New Apps Only)
- Creates `winit-testabc/{app-name}-main` repository if it doesn't exist
- Initializes with basic README.md and .gitignore
- Pushes initial commit to GitHub
- Sets repository as private by default

### 3. Creates/Updates Kubernetes Manifests
Creates or updates files in `k8s-production/apps/{app-name}/`:
- `{app-name}.yaml` - Deployment and Service manifests
- `README.md` - Documentation with deployment instructions

**Environment Support**:
- **Production**: Deploys to `production` namespace
- **Staging**: Deploys to `staging` namespace
- Manifests are automatically configured with the correct namespace

### 4. Manages Ingress Routes
- **Add routes**: Configure domain-to-port mappings
- **Remove routes**: Delete existing ingress routes
- Routes are added to `k8s-production/apps/tunnel-ingress/tunnel-ingress.yaml`
- Routes are added to the appropriate namespace section (production or staging)
- Creates the staging section automatically if it doesn't exist

### 5. Commits and Pushes Changes
- Automatically commits all changes to k8s-production
- Pushes to GitHub repository
- For new apps, also creates and initializes app source repository
- No manual git commands needed!

## Example Session

### Creating a New App

```bash
$ ./setup-app.sh payment-service

============================================================================
🚀 App Configuration Script
============================================================================

ℹ App 'payment-service' not found (new app)

============================================================================
Configure New App: payment-service
============================================================================

→ 1. Configure app settings (replicas, resources, port)
→ 2. Manage ingress routes
→ 3. Save and push changes to GitHub
→ 4. Exit without saving

? Choose an option: 1

? Configure for which environment? (production/staging) [default: production]: production
? Enter number of replicas [default: 1]: 2
? Enter memory request [default: 256Mi]: 512Mi
? Enter memory limit [default: 512Mi]: 1Gi
? Enter CPU request [default: 100m]: 200m
? Enter CPU limit [default: 250m]: 500m
? Enter container port [default: 3000]: 3000
✅ Created/updated k8s-production/apps/payment-service/payment-service.yaml
✅ Created/updated README

? Choose an option: 2

============================================================================
Ingress Routes Management for payment-service
============================================================================
No ingress routes configured.

→ 1. Add ingress route
→ 2. Remove ingress route
→ 3. Done with ingress configuration

? Choose an option: 1

? Enter domain name (e.g., myapp.winit.dev): api-payment.winit.dev
? Enter local port for api-payment.winit.dev [default: 3000]: 3000
✅ Added ingress route: api-payment.winit.dev -> payment-service:3000

? Choose an option: 3

? Choose an option: 3

ℹ Committing changes...
✅ Changes pushed to GitHub
ℹ Checking for app source repository: winit-testabc/payment-service-main
? Create new GitHub repository 'winit-testabc/payment-service-main' for app source code? (Y/n): y
ℹ Creating repository: winit-testabc/payment-service-main
✅ Created repository: winit-testabc/payment-service-main
ℹ Initializing repository with basic structure...
✅ Repository initialized and pushed to GitHub
ℹ Repository URL: https://github.com/winit-testabc/payment-service-main
✅ Configuration complete!
```

### Editing an Existing App

```bash
$ ./setup-app.sh payment-service

✅ App 'payment-service' found (existing app)

Current configuration:
  Environment: production (namespace: production)
  Replicas: 2
  Container Port: 3000
  Resources: 512Mi/1Gi memory, 200m/500m CPU

? Choose an option: 1

? Environment [current: production] (press Enter to keep, or enter new): 
? Number of replicas [current: 2] (press Enter to keep): 3
✅ Created/updated k8s-production/apps/payment-service/payment-service.yaml

? Choose an option: 3
✅ Changes pushed to GitHub
```

## Generated Manifest Structure

The script generates a standard Kubernetes manifest with:

- **Deployment**: Configured with your specified replicas, resources, and port
- **Service**: ClusterIP service exposing your container port
- **Health Checks**: Standard liveness and readiness probes
- **Labels**: Properly labeled for Fargate and ArgoCD discovery

## What Happens After Configuration

The script automatically:
1. ✅ Creates/updates Kubernetes manifests
2. ✅ Updates ingress routes
3. ✅ Commits changes to git
4. ✅ Pushes to GitHub

**No manual git commands needed!**

After the script completes:
- ArgoCD will automatically sync the changes
- Your app will be deployed/updated in Kubernetes
- Ingress routes will be active (if configured)

To manually deploy a new version:
```bash
./scripts/deploy-app.sh {app-name} v1.0.0-{environment} {GITHUB_ORG}/{app-name}-main
```

## Notes

- **Automatically commits and pushes** - No manual git commands needed
- **Edit existing apps** - Shows current values, allows incremental updates
- **Menu-driven** - Easy to navigate and make changes
- **Automatically clones k8s-production** if it doesn't exist locally
- Uses GitHub CLI (`gh`) for all GitHub operations
- Ingress routes can be added or removed interactively
- All paths are relative to where you run the script from
- The script can be run from any directory

## Troubleshooting

**GitHub CLI not authenticated**:
```bash
gh auth login
```

**Repository creation fails**:
- Check you have permissions in the `winit-testabc` organization
- Create the repository manually at: https://github.com/organizations/winit-testabc/repositories/new

**Ingress file not found**:
- Ensure you're running from the correct directory
- Check that `k8s-production/apps/tunnel-ingress/tunnel-ingress.yaml` exists

