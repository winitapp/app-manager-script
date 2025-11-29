# App Manager Script

Interactive script to configure Kubernetes apps, manage ingress routes, and deploy applications.

**Repository**: https://github.com/winit-testabc/app-manager-script (Public)


## Quick Start

### One-Liners (Copy & Paste)

**Linux/macOS/Git Bash:**
```bash
curl -fsSL https://raw.githubusercontent.com/winit-testabc/app-manager-script/main/setup-app.sh -o setup-app.sh && chmod +x setup-app.sh && ./setup-app.sh
```

**Windows PowerShell:**
```powershell
irm https://raw.githubusercontent.com/winit-testabc/app-manager-script/main/setup-app.sh -OutFile setup-app.sh; if ($?) { chmod +x setup-app.sh; ./setup-app.sh }
```

**Windows CMD:**
```cmd
curl -fsSL https://raw.githubusercontent.com/winit-testabc/app-manager-script/main/setup-app.sh -o setup-app.sh && chmod +x setup-app.sh && setup-app.sh
```

## Prerequisites

- **GitHub CLI (`gh`)** installed and authenticated
- Access to the `winit-testabc` GitHub organization

**Install GitHub CLI:**

```bash
# macOS
brew install gh

# Linux (Debian/Ubuntu)
sudo apt install gh

# Linux (RHEL/CentOS/Fedora)
sudo yum install gh  # or sudo dnf install gh

# Windows
winget install GitHub.cli
```

**Authenticate:**

```bash
gh auth login
```

## Features

- ✅ **Create new apps** - Set up complete Kubernetes manifests
- ✅ **Edit existing apps** - Modify replicas, resources, ports, ingress routes
- ✅ **Create app repositories** - Automatically creates GitHub repo for app source code
- ✅ **Ingress management** - Add, remove, or edit ingress routes interactively
- ✅ **View configuration** - See current app settings in a formatted table
- ✅ **Get deploy script** - Generate a custom deployment script for your app
- ✅ **Auto-commit & push** - Automatically commits and pushes changes to GitHub
- ✅ **Environment support** - Configure for production or staging

## Usage

Run the script and follow the interactive menu:

```bash
./setup-app.sh
```

**Menu Options:**
1. **Configure app settings** - Set replicas, CPU, memory, container port, environment
2. **Manage ingress routes** - Add or remove domain-to-port mappings
3. **View current configuration** - Display current settings in a table format
4. **Get deploy script** - Generate a custom deployment script (see below)
5. **Save and push changes** - Commit and push to GitHub
6. **Exit without saving**

## Deploy Script

The **"Get deploy script"** option generates a custom deployment script (`{app-name}-deploy.sh`) for your app. This script:

- **Prompts for environment** (production/staging)
- **Auto-detects latest version** from existing tags in the k8s repository
- **Suggests next version** (auto-increments patch version)
- **Checks for pending changes** and asks if you want to commit them
- **Triggers deployment workflow** in the k8s repository
- **Monitors deployment progress** and shows workflow status

**Usage:**
```bash
./{app-name}-deploy.sh
```

The script is pre-configured with your app name and will guide you through the deployment process interactively.

## What It Does

1. **Clones/updates k8s repository** - Automatically manages `k8s-production` or `k8s-staging`
2. **Creates/updates Kubernetes manifests** - Generates Deployment and Service YAML files
3. **Manages ingress routes** - Adds domain routes to Cloudflare Tunnel ingress configuration
4. **Creates app source repository** - Sets up GitHub repo for your app code (if new app)
5. **Commits and pushes** - Automatically commits all changes and pushes to GitHub

## Example Workflow

```bash
# 1. Run the setup script
./setup-app.sh

# 2. Enter app name when prompted
? Enter app name: payment-service

# 3. Configure app settings (Option 1)
? Configure for which environment? (production/staging): production
? Enter number of replicas [default: 1]: 2
? Enter memory request [default: 256Mi]: 512Mi
...

# 4. Add ingress routes (Option 2)
? Enter domain name: api-payment.winit.dev
? Enter local port [default: 3000]: 3000

# 5. Save and push (Option 5)
✅ Changes pushed to GitHub

# 6. Get deploy script (Option 4)
✅ Created deploy script: payment-service-deploy.sh

# 7. Deploy your app
./payment-service-deploy.sh
```

## After Configuration

- ✅ ArgoCD automatically syncs changes
- ✅ Your app is deployed/updated in Kubernetes
- ✅ Ingress routes become active (if configured)

No manual git commands needed!

## Troubleshooting

**GitHub CLI not authenticated:**
```bash
gh auth login
```

**Repository creation fails:**
- Check you have permissions in the `winit-testabc` organization
- Create the repository manually at: https://github.com/organizations/winit-testabc/repositories/new

**Script hangs:**
- Make sure you downloaded the script first (don't pipe directly to bash)
- Use the one-liner which downloads before executing
