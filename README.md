# Kubernetes on Proxmox Infrastructure

This project provides a complete, production-ready Kubernetes platform on Proxmox VMs with comprehensive DevOps tooling, observability, automation, security, and application hosting capabilities.

## 🎯 Platform Capabilities Summary

This infrastructure provides:

- **Self-Hosted Kubernetes Platform**: k3s-based cluster with high availability
- **Complete Observability**: Metrics, logs, traces, and dashboards
- **Automation & Workflows**: Multiple workflow automation platforms
- **Security & Identity**: SSO, secrets management, and certificate automation
- **Application Hosting**: WordPress sites, documentation, and custom applications
- **Backup & Recovery**: Comprehensive backup systems for all workloads
- **Network Security**: VPN bridging, firewall configuration, load balancing

See [Detailed Capabilities](#detailed-capabilities) section below for complete feature list.

## Project Structure

The project is organized with proper Terraform modules and clean directory structure:

```
.
├── .vscode/                       # IDE configuration files
│   ├── .cursorrules               # Cursor AI rules
│   └── epyc.code-workspace        # VS Code workspace
├── modules/                       # Terraform modules
│   ├── proxmox/                   # Proxmox VM provisioning (3-node cluster)
│   ├── kubernetes/                # Kubernetes infrastructure (MetalLB, NFS)
│   ├── monitoring/                # Observability stack (Prometheus, Grafana, Loki, Tempo)
│   ├── cert-manager/              # Automated certificate management (Let's Encrypt)
│   └── ingress/                   # Ingress controllers (Traefik)
├── kubernetes/                    # Kubernetes application manifests
│   ├── activepieces/              # Workflow automation platform (alternative to Zapier)
│   ├── airflow/                   # Apache Airflow data orchestration
│   ├── ethosenv-k8s/              # WordPress site (ethos.gray-beard.com)
│   ├── grafana/                   # Grafana dashboards and integrations
│   ├── keycloak/                  # Single Sign-On (SSO) authentication
│   ├── n8n/                       # n8n workflow automation
│   ├── ntfy/                      # ntfy notification service
│   ├── nozyu/                     # Custom application (Go/TypeScript)
│   ├── obsidian/                  # Obsidian Sync with CouchDB
│   ├── vault/                     # HashiCorp Vault secrets management
│   ├── wordpress/                 # WordPress site (kampfzwerg.gray-beard.com)
│   ├── metallb-configurations/    # Load balancer IP pools
│   ├── monitoring/                # Monitoring stack configs
│   └── traefik/                   # Ingress controller configs
├── scripts/                       # Management and utility scripts (50+ scripts)
│   ├── backup-*.sh                # Backup automation for all sites
│   ├── setup-*.sh                 # Infrastructure setup scripts
│   ├── fix-*.sh                   # Troubleshooting and repair scripts
│   ├── diagnose-*.sh              # Diagnostic scripts
│   └── README.md                  # Scripts documentation
├── docs/                          # Comprehensive documentation
│   ├── REVERSE-PROXY-SETUP.md     # Nginx reverse proxy guide
│   ├── network-bridge.md          # WireGuard VPN bridge setup
│   ├── opnsense-wireguard-setup.md # OPNsense VPN configuration
│   ├── traefik-external-connectivity-fix.md # MetalLB troubleshooting
│   ├── proxmox-metallb-subnet-configuration.md # Network routing
│   └── README.md                  # Documentation index
├── config/                        # Configuration files
│   ├── nginx/                     # Nginx reverse proxy configs
│   │   ├── nginx-reverse-proxy.conf    # Main proxy configuration
│   │   ├── ssl-params.conf             # TLS/SSL settings
│   │   └── security-headers.conf       # Security headers
│   ├── k3s/                       # Kubernetes cluster configuration
│   └── README.md                  # Configuration documentation
├── backups/                       # Backup storage
│   ├── ethosenv/                  # EthosEnv WordPress backups
│   ├── n8n/                       # n8n backup archives
│   ├── wordpress/                 # Kampfzwerg WordPress backups
│   └── README.md                  # Backup system documentation
├── charts/                        # Helm charts
│   └── wordpress-site/            # Custom WordPress Helm chart
├── templates/                     # Terraform templates
│   ├── cloud-init-userdata.tftpl  # VM initialization template
│   └── ssh_config.tftpl           # SSH configuration template
├── main.tf                        # Root Terraform configuration
├── variables.tf                   # Root variables
├── outputs.tf                     # Root outputs
├── terraform.tfvars               # Variable values (not in git)
├── kubeconfig.yaml                # Kubernetes configuration
└── README.md                      # This file
```

## Quick Start

### 🚀 Infrastructure Setup
```bash
# 1. Set up reverse proxy (run on control plane node)
./scripts/setup-reverse-proxy.sh

# 2. Test all services
./scripts/test-all-domains.sh

# 3. Get SSL certificates (optional)
./scripts/setup-letsencrypt.sh
```

### 📚 Documentation

#### Getting Started
- **Documentation Index**: [`docs/README.md`](docs/README.md) - Start here for navigation
- **Complete Setup Guide**: [`docs/REVERSE-PROXY-SETUP.md`](docs/REVERSE-PROXY-SETUP.md)
- **Scripts Reference**: [`scripts/README.md`](scripts/README.md) - 50+ management utilities
- **Configuration Guide**: [`config/README.md`](config/README.md)

#### Infrastructure Documentation
- **Network Bridge Setup**: [`docs/network-bridge.md`](docs/network-bridge.md) - WireGuard VPN configuration
- **OPNsense Configuration**: [`docs/opnsense-wireguard-setup.md`](docs/opnsense-wireguard-setup.md)
- **MetalLB Configuration**: [`docs/proxmox-metallb-subnet-configuration.md`](docs/proxmox-metallb-subnet-configuration.md)
- **Traefik Connectivity**: [`docs/traefik-external-connectivity-fix.md`](docs/traefik-external-connectivity-fix.md)
- **Network Bridge Checklist**: [`docs/network-bridge-checklist.md`](docs/network-bridge-checklist.md)

#### Application Documentation
- **Vault Setup**: [`kubernetes/vault/README.md`](kubernetes/vault/README.md) - Secrets management
- **Keycloak SSO**: [`kubernetes/keycloak/README.md`](kubernetes/keycloak/README.md) - Authentication
- **Activepieces**: [`kubernetes/activepieces/README.md`](kubernetes/activepieces/README.md) - Workflow automation
- **Obsidian Sync**: [`kubernetes/obsidian/README.md`](kubernetes/obsidian/README.md) - Note synchronization
- **WordPress (ethos)**: [`kubernetes/ethosenv-k8s/README.md`](kubernetes/ethosenv-k8s/README.md)
- **Monitoring Stack**: [`kubernetes/README-monitoring.md`](kubernetes/README-monitoring.md) - k3s-specific config

#### Backup & Recovery
- **Backup System**: [`backups/README.md`](backups/README.md) - Comprehensive backup documentation

#### Project Organization
- **Organization Summary**: [`docs/ORGANIZATION-SUMMARY.md`](docs/ORGANIZATION-SUMMARY.md)
- **Git Cleanup**: [`docs/GIT-CLEANUP-SUMMARY.md`](docs/GIT-CLEANUP-SUMMARY.md)

## Prerequisites

- Proxmox server with API access
- SSH keypair for VM access
- Terraform installed locally

## Two-Phase Deployment

The deployment is split into two phases:

### Phase 1: Infrastructure Deployment

```bash
# Initialize Terraform
terraform init

# Create the VMs and basic infrastructure
terraform apply -var="deploy_kubernetes=false"

# After VMs are created:
# 1. SSH to the control node
ssh -F ssh_config gimli

# 2. Verify k3s is running on the control node
sudo systemctl status k3s

# 3. Copy the kubeconfig from the control node
scp -F ssh_config gimli:/etc/rancher/k3s/k3s.yaml ./kubeconfig.yaml

# 4. Update the server address in the kubeconfig
sed -i '' 's/127.0.0.1/CONTROL_NODE_PRIVATE_IP/g' kubeconfig.yaml
```

### Phase 2: Kubernetes Resources Deployment

```bash
# Deploy Kubernetes resources and monitoring stack
terraform apply -var="deploy_kubernetes=true"
```

## Architecture Overview

### System Architecture Diagram

![Kubernetes Services Architecture](kubernetes-services-diagram.png)

This diagram illustrates the complete architecture of the project, showing the relationships and dependencies between all components across multiple layers.

### Architecture Layers

#### 1. Infrastructure Layer
- **Proxmox Hypervisor**: VM provisioning and management
- **3-Node k3s Cluster**: 
  - gimli (control plane)
  - legolas (worker)
  - aragorn (worker)
- **Storage**: NFS provisioner for persistent volumes (128GB per node)
- **Networking**: 
  - Public bridge (vmbr1): 10.0.1.0/24
  - Private bridge (vmbr2): 192.168.100.0/24
  - MetalLB pool: 10.0.2.8/29
  - WireGuard VPN: Secure bridge to home network

#### 2. Core Platform Services
- **Traefik Ingress Controller**: 
  - HTTP/HTTPS routing (LoadBalancer IP: 10.0.2.9)
  - Automatic TLS termination
  - WebSocket support
- **Cert-Manager**: Automated Let's Encrypt certificates
- **MetalLB**: Layer 2 load balancing for bare metal
- **Nginx Reverse Proxy**: External traffic handling on standard ports

#### 3. Security & Identity Layer
- **HashiCorp Vault** (vault.gray-beard.com):
  - Centralized secrets management
  - Kubernetes secrets synchronization
  - Encrypted credential storage
- **Keycloak** (login.gray-beard.com):
  - Single Sign-On (SSO)
  - OpenID Connect / OAuth 2.0
  - User directory and RBAC

#### 4. Observability Stack
- **Metrics Collection**:
  - Prometheus: Time-series database
  - Mimir: Long-term metrics storage
  - ServiceMonitors: Automatic discovery
- **Visualization**:
  - Grafana (grafana.gray-beard.com): Dashboards and alerts
  - 15+ pre-configured dashboards
- **Logging**:
  - Loki: Log aggregation
  - Promtail: Log collection agents
- **Tracing**:
  - Tempo: Distributed tracing
- **Alerting**:
  - AlertManager: Alert routing and notifications
  - Email integration for critical alerts

#### 5. Automation & Workflow Layer
- **n8n** (automate.gray-beard.com):
  - 200+ integrations
  - Webhook and scheduled triggers
  - PostgreSQL backend
- **Activepieces** (automate2.gray-beard.com):
  - Open-source Zapier alternative
  - Redis queue management
  - Team collaboration
- **ntfy** (notify.gray-beard.com):
  - Push notification service
  - HTTP-based pub/sub
  - Grafana alert integration

#### 6. Application Layer
- **WordPress Sites**:
  - ethos.gray-beard.com: Production WordPress (MySQL 8.0)
  - kampfzwerg.gray-beard.com: German WordPress site
  - WP-CLI management
  - Automated daily backups
- **Obsidian Sync** (blackrock.gray-beard.com):
  - Self-hosted synchronization
  - CouchDB backend
  - End-to-end encryption support
- **Custom Applications**:
  - Nozyu: Go/TypeScript microservices

#### 7. Data & Backup Layer
- **Database Backups**: MySQL dumps with verification
- **File Backups**: Compressed archives (1.5GB+ total)
- **Backup Automation**: Daily scheduled backups
- **Retention Management**: Automatic cleanup
- **Restoration Procedures**: Tested recovery workflows

### Key Architecture Relationships

#### Traffic Flow
```
Internet → Nginx Reverse Proxy (80/443)
    ↓
Traefik Ingress (MetalLB: 10.0.2.9)
    ↓
Service Routing (based on Host headers)
    ↓
Application Pods (Kubernetes Services)
```

#### Authentication Flow
```
User → Application
    ↓
Redirect to Keycloak (login.gray-beard.com)
    ↓
OpenID Connect / OAuth 2.0
    ↓
Token → Application
    ↓
Authorized Access
```

#### Monitoring Data Flow
```
Application Pods → Prometheus (metrics scraping)
                 → Promtail (log collection)
                 → Tempo (trace collection)
    ↓
Prometheus → Mimir (long-term storage)
Promtail → Loki (log storage)
Tempo → Tempo backend
    ↓
Grafana → Query all sources
       → Display dashboards
       → Trigger alerts
    ↓
AlertManager → Email notifications
```

#### Secrets Management Flow
```
Vault (vault.gray-beard.com)
    ↓
Vault Secrets Operator
    ↓
Kubernetes Secrets
    ↓
Application Pods (environment variables)
```

### Network Topology
```
Internet
    ↓
Gateway/Firewall (10.0.1.209)
    ↓
Proxmox Host
    ├── vmbr1 (Public Bridge)
    │   ├── Node IPs: 10.0.1.211-213
    │   └── MetalLB Pool: 10.0.2.8/29
    │       └── Traefik LB: 10.0.2.9
    └── vmbr2 (Private Bridge)
        └── Private Network: 192.168.100.0/24
            └── Inter-node communication

WireGuard VPN Tunnel
    ├── Colocation (10.10.10.2)
    └── Home Network (10.10.10.1) via OPNsense
        └── Backup: Tailscale mesh network
```

## Modules

### Proxmox Module

Creates Proxmox VMs with the following features:
- Public and private networking
- Cloud-init for initial configuration
- K3s installation

### Kubernetes Module

Sets up core Kubernetes infrastructure:
- MetalLB for LoadBalancer services
- NFS storage for persistent volumes

### Monitoring Module

Deploys a comprehensive observability stack:
- Prometheus for metrics
- Grafana for visualization
- Loki for logs
- Tempo for tracing
- Mimir for long-term metrics storage

## Detailed Capabilities

### 🏗️ Infrastructure Foundation

#### Compute & Virtualization
- **3-Node k3s Cluster**: Lightweight Kubernetes with control plane HA
- **Proxmox Integration**: Automated VM provisioning via Terraform
- **Resource Management**: 8 cores, 16GB RAM per node (48GB total cluster)
- **Cloud-Init**: Automated VM configuration and bootstrapping

#### Networking
- **MetalLB**: Layer 2 load balancing with dedicated IP pools
- **Traefik Ingress**: Automatic routing, SSL termination, WebSocket support
- **WireGuard VPN**: Secure network bridge between colocation and home network
- **Nginx Reverse Proxy**: External traffic handling on standard ports (80/443)
- **Multiple Subnets**: Public (10.0.1.0/24), Private (192.168.100.0/24), MetalLB (10.0.2.8/29)

#### Storage
- **NFS Provisioner**: Dynamic persistent volume provisioning
- **Persistent Volumes**: 128GB per node for application data
- **Backup Storage**: Organized backup system with 1.5GB+ capacity

### 🔐 Security & Identity

#### Certificate Management
- **Cert-Manager**: Automated Let's Encrypt certificate provisioning
- **Dual Issuers**: Production and staging certificate environments
- **Auto-Renewal**: Automatic certificate rotation before expiration
- **TLS 1.2/1.3**: Modern cipher suites and security headers

#### Secrets Management
- **HashiCorp Vault**: Centralized secrets storage and management
- **Vault Secrets Operator**: Automatic secret sync to Kubernetes
- **Encrypted Storage**: Secure credential storage with UI and CLI access
- **Secret Rotation**: Support for regular credential rotation

#### Authentication & Authorization
- **Keycloak SSO**: Single Sign-On for all applications
- **OIDC Integration**: OAuth/OpenID Connect for Grafana, n8n, WordPress
- **Centralized User Management**: Unified user directory and authentication
- **Access Control**: Role-based access control across platforms

### 📊 Observability & Monitoring

#### Metrics & Visualization
- **Prometheus**: Time-series metrics collection and storage
- **Grafana**: Beautiful dashboards with 15+ pre-configured views
- **Mimir**: Long-term metrics storage with high availability
- **AlertManager**: Intelligent alerting with email notifications
- **Custom Dashboards**: Service-specific monitoring (n8n, CouchDB, WordPress, ntfy)

#### Logging & Tracing
- **Loki**: Centralized log aggregation and querying
- **Promtail**: Log collection from all nodes and containers
- **Tempo**: Distributed tracing for microservices
- **Log Retention**: Configurable retention policies

#### Health & Diagnostics
- **Service Monitors**: Automatic service discovery and monitoring
- **Health Checks**: Comprehensive diagnostic scripts (50+ utilities)
- **Performance Metrics**: CPU, memory, disk, network tracking
- **k3s-Optimized**: Custom alert suppression for k3s architecture

### 🤖 Automation & Workflows

#### Workflow Platforms
- **n8n**: Visual workflow automation (primary platform)
  - 200+ integrations, webhooks, scheduled triggers
  - Kubernetes-native deployment with persistent storage
  - Prometheus metrics and Grafana dashboards
  
- **Activepieces**: Alternative workflow automation
  - Open-source Zapier alternative
  - PostgreSQL backend with Redis queue
  - Team collaboration features
  
- **Apache Airflow**: Data orchestration (configurable)
  - DAG-based workflow management
  - Python-based task definitions

#### Notification System
- **ntfy**: Push notification service
  - Self-hosted notification delivery
  - HTTP-based API
  - Integration with Grafana for alerts
  - Custom dashboard for monitoring

### 🌐 Application Hosting

#### WordPress Sites (2 Production Instances)
- **ethos.gray-beard.com**: Production WordPress site
  - MySQL 8.0 backend
  - Automatic SSL via cert-manager
  - WP-CLI for management
  - Comprehensive backup system (406MB database + files)
  
- **kampfzwerg.gray-beard.com**: WordPress site
  - Full WordPress stack
  - Resource-optimized deployment
  - Automated backups (1.1GB total)

#### Documentation & Knowledge Management
- **Obsidian Sync**: Self-hosted Obsidian synchronization
  - CouchDB database backend
  - blackrock.gray-beard.com domain
  - SSL certificate management
  - Persistent storage for notes

#### Custom Applications
- **Nozyu**: Custom application platform
  - Go and TypeScript codebase
  - Microservices architecture
  - Kubernetes-native deployment

### 💾 Backup & Disaster Recovery

#### Automated Backup System
- **Backup Manager**: Centralized backup orchestration
- **Database Backups**: Complete MySQL dumps with verification
- **File Backups**: Compressed tar.gz archives
- **Metadata Tracking**: JSON manifests with backup details
- **Multi-Site Support**: EthosEnv and Kampfzwerg coverage

#### Backup Features
- **Dynamic Pod Detection**: Automatic resource discovery
- **Integrity Verification**: Checksum validation and content testing
- **Retention Management**: Automatic cleanup of old backups
- **Restoration Scripts**: Tested recovery procedures
- **Total Protected Data**: 1.5GB+ across 32,000+ files

#### Backup Metrics
| Site | Database | Files | Tables | File Count |
|------|----------|-------|--------|------------|
| EthosEnv | 5.3MB | 401MB | 50 | 15,966 |
| WordPress | 1.5MB | 1.1GB | 22 | 16,235 |

### 🔧 DevOps & Management

#### Infrastructure as Code
- **Terraform**: Complete infrastructure automation
- **Modular Design**: Reusable Terraform modules
- **Provider Support**: Proxmox, Kubernetes, Helm
- **State Management**: Terraform state with backups

#### Management Scripts (50+ Utilities)
- **Setup Scripts**: Infrastructure initialization and configuration
- **Backup Scripts**: Automated backup creation and verification
- **Diagnostic Scripts**: Health checks and troubleshooting
- **Fix Scripts**: Automated problem resolution
- **Migration Scripts**: Service and data migration tools

#### Helm Charts
- **Custom WordPress Chart**: Production-ready WordPress Helm chart
- **Templated Deployments**: Configurable application deployments
- **Values Management**: Environment-specific configurations

### 📡 Network Bridge Architecture

#### VPN Connectivity
- **Primary**: WireGuard tunnel between colocation and home
- **Backup**: Tailscale for redundant connectivity
- **OPNsense Integration**: Firewall and routing configuration
- **Secure Transit**: All traffic encrypted in transit
- **Monitoring**: Connection health checks and failover

#### Network Topology
```
Internet → Gateway (10.0.1.209)
    ↓
Proxmox Host
    ↓
vmbr1 (Public Bridge)
    ├── K8s Nodes (10.0.1.211-213)
    └── MetalLB Pool (10.0.2.8/29)
        ↓
    Traefik Ingress (10.0.2.9)
        ↓
    Application Services
```

## Services

The project deploys the following production services:

### Core Infrastructure

#### Traefik Ingress Controller
- Automatic TLS termination with Let's Encrypt
- Host-based routing for all services
- WebSocket support for real-time applications
- LoadBalancer service via MetalLB

#### Cert-Manager
- Automated certificate provisioning and renewal
- Production and staging Let's Encrypt issuers
- Certificate monitoring and alerts
- Support for multiple domains and wildcards

### Workflow Automation

#### n8n (automate.gray-beard.com)
- Visual workflow builder with 200+ integrations
- Webhook triggers and scheduled workflows
- PostgreSQL persistent storage
- Prometheus metrics and custom Grafana dashboard
- SSO integration via Keycloak

#### Activepieces (automate2.gray-beard.com)
- Open-source automation alternative to Zapier
- PostgreSQL + Redis architecture
- Team collaboration features
- Self-hosted with no telemetry

### Identity & Security

#### Keycloak (login.gray-beard.com)
- Single Sign-On (SSO) provider
- OpenID Connect / OAuth 2.0
- Centralized user management
- Integration with Grafana, n8n, WordPress

#### HashiCorp Vault (vault.gray-beard.com)
- Secrets management and encryption
- Kubernetes secrets synchronization
- Web UI and CLI access
- Credential rotation support

### Monitoring & Observability

#### Grafana (grafana.gray-beard.com)
- 15+ pre-configured dashboards
- Integration with Prometheus, Loki, Tempo
- Custom dashboards for all services
- SSO authentication via Keycloak
- Alert visualization and management

#### Prometheus Stack
- Metrics collection from all services
- ServiceMonitor auto-discovery
- Long-term storage with Mimir
- AlertManager for notifications

#### Loki + Promtail
- Centralized log aggregation
- Label-based log querying
- Integration with Grafana
- Log retention policies

#### Tempo
- Distributed tracing
- Trace visualization in Grafana
- Performance bottleneck identification

### Applications

#### WordPress Sites
- **ethos.gray-beard.com**: Production WordPress with SSL
- **kampfzwerg.gray-beard.com**: WordPress site with German content
- MySQL 8.0 databases
- WP-CLI for management
- Automated daily backups
- Resource-optimized deployments

#### Obsidian Sync (blackrock.gray-beard.com)
- Self-hosted synchronization server
- CouchDB for document storage
- End-to-end encryption support
- Custom Grafana dashboard for monitoring
- SSL with automatic certificate renewal

#### ntfy (notify.gray-beard.com)
- Push notification service
- HTTP-based pub/sub messaging
- Integration with Grafana for alerts
- Custom monitoring dashboard

## Monitoring

The project includes a comprehensive monitoring stack:

### Alertmanager

- Email notifications for alerts
- Configured with appropriate inhibition rules
- Customized for k3s environments

### Grafana Dashboards

- Kubernetes system resources
- Node resources
- Custom dashboards for all services (n8n, CouchDB, Obsidian)

## Accessing Services

### Web-Accessible Services

All services are accessible via HTTPS with automatic SSL certificates:

| Service | URL | Purpose |
|---------|-----|---------|
| Grafana | `https://grafana.gray-beard.com` | Monitoring dashboards |
| Vault | `https://vault.gray-beard.com` | Secrets management |
| Keycloak | `https://login.gray-beard.com` | Single Sign-On |
| n8n | `https://automate.gray-beard.com` | Workflow automation |
| Activepieces | `https://automate2.gray-beard.com` | Alternative automation |
| ntfy | `https://notify.gray-beard.com` | Push notifications |
| Obsidian | `https://blackrock.gray-beard.com` | Note synchronization |
| WordPress (Ethos) | `https://ethos.gray-beard.com` | WordPress site |
| WordPress (Kampfzwerg) | `https://kampfzwerg.gray-beard.com` | WordPress site |

### Port-Forward Access

For services without ingress or local development:

#### Grafana
```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
# Open http://localhost:3000
# Username: admin, Password: from terraform.tfvars
```

#### Traefik Dashboard
```bash
kubectl port-forward svc/traefik 9000:9000 -n kube-system
# Open http://localhost:9000/dashboard/
```

#### Prometheus
```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# Open http://localhost:9090
```

#### CouchDB (Obsidian Sync)
```bash
kubectl port-forward svc/couchdb 9984:5984 -n obsidian
# Open http://localhost:9984
```

#### Vault
```bash
kubectl port-forward svc/vault 8200:8200 -n vault
# Open http://localhost:8200
```

## Notes

- Keep `terraform.tfvars` and secrets secure
- The node token file should not be committed to version control
- For k3s-specific monitoring configuration, see `kubernetes/README-monitoring.md`
- Alert notifications are configured to use email via Alertmanager

## Secure Credentials Management

This project uses HashiCorp Vault for secure credential management. All sensitive information is stored in Vault and retrieved by applications at runtime, rather than being stored in manifest files.

### Vault Setup

To deploy and configure the Vault server:

```bash
# Deploy Vault with secure credentials
cd kubernetes/vault
VAULT_PASSWORD="your-secure-password" SMTP_PASSWORD="your-email-app-password" ./deploy-vault.sh

# Deploy the Vault Secrets Operator to sync credentials to Kubernetes
./deploy-secrets-operator.sh
```

### Accessing the Vault

1. **Web UI Access**:
   - The Vault UI is available at `https://vault.gray-beard.com`
   - Use the initial root password: `********` (refer to the deployment script)

2. **CLI Access**:
   - Source the credentials file to load environment variables:
     ```bash
     source ~/.vault/credentials
     ```
   - Access Vault using the CLI:
     ```bash
     export VAULT_ADDR=https://vault.gray-beard.com
     vault login -method=token "$VAULT_ROOT_TOKEN"
     ```

### Stored Credentials

The following credentials are securely stored in Vault:

- **AlertManager**: Email SMTP configuration
- **n8n**: Admin username and password
- **CouchDB**: Database credentials for Obsidian sync
- **K3s**: Cluster token

### Updating Secrets

To update a secret:

```bash
# Export variables from the credentials file
source ~/.vault/credentials

# Update a secret using the Vault CLI
export VAULT_ADDR=https://vault.gray-beard.com
vault kv put secret/n8n admin_password="********" admin_user="admin"
```

### Security Notes

- After first login, change the root token and initial password
- Back up the ~/.vault/credentials file to a secure location
- Avoid committing any plain-text credentials to version control