# Kubernetes on Proxmox Infrastructure

This project sets up a Kubernetes cluster on Proxmox VMs and deploys a complete observability stack including Prometheus, Grafana, Loki, Tempo, and more.

## Project Structure

The project is organized with proper Terraform modules:

```
.
├── modules/                       # Terraform modules
│   ├── proxmox/                   # Proxmox VM provisioning
│   │   ├── main.tf                # VM creation logic
│   │   ├── variables/             # Module input variables
│   │   ├── outputs/               # Module outputs
│   │   └── snippets/              # Helper code snippets
│   ├── kubernetes/                # Kubernetes infrastructure
│   │   ├── main.tf                # K8s resources (MetalLB, NFS)
│   │   ├── variables/             # Module input variables
│   │   └── outputs/               # Module outputs
│   ├── monitoring/                # Observability stack
│   │   ├── main.tf                # Monitoring components
│   │   ├── variables/             # Module input variables
│   │   ├── outputs/               # Module outputs
│   │   └── templates/             # Configuration templates
│   ├── cert-manager/              # Certificate management
│   │   ├── templates/             # Configuration templates
│   │   └── variables/             # Module input variables
│   └── ingress/                   # Ingress controllers
├── kubernetes/                    # Kubernetes manifests
│   ├── alertmanager-config.yaml   # Alertmanager email notifications
│   ├── apply-alertmanager-config.sh # Script to apply alerting config
│   ├── grafana/                   # Grafana-related manifests
│   │   └── grafana-ingress-tls.yaml # TLS-enabled ingress
│   ├── k3s-cleanup-servicemonitors.sh # Fix k3s monitoring
│   ├── n8n/                       # n8n automation platform manifests
│   │   ├── deployment.yaml        # n8n deployment configuration
│   │   └── ingress-tls.yaml       # TLS-enabled ingress for n8n
│   ├── obsidian/                  # Obsidian sync manifests
│   │   ├── couchdb-deployment.yaml # CouchDB for Obsidian sync
│   │   └── obsidian-deployment.yaml # Obsidian server
│   ├── prometheus-rule-suppress.yaml # Alert suppression rules
│   ├── README-monitoring.md       # Monitoring documentation
│   └── traefik/                   # Traefik ingress controller manifests
│       ├── current-traefik.yaml   # Current Traefik configuration
│       └── traefik-deployment-acme.yaml # ACME/Let's Encrypt enabled
├── config/                        # Configuration files
│   └── k3s/                       # k3s config files
├── templates/                     # General templates
├── snippets/                      # Helper code snippets
├── main.tf                        # Root Terraform configuration
├── variables.tf                   # Root variables
├── outputs.tf                     # Root outputs
├── terraform.tfvars               # Variable values (not in git)
├── nok8s.tfvars                   # Infrastructure-only variables
├── kubeconfig.yaml                # Kubernetes configuration
└── cloud-init-userdata.tftpl      # Template for cloud-init configuration
```

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

## Services

The project also sets up these additional services (via Kubernetes manifests):

### Traefik

- Ingress controller with automatic TLS
- ACME/Let's Encrypt integration

### n8n

- Workflow automation tool
- Prometheus metrics integration
- Configurable with authentication
- Integration with Grafana dashboards

### Obsidian Sync

- Self-hosted Obsidian sync server
- CouchDB backend for data storage
- Monitoring with Prometheus
- Visualization with Grafana dashboards

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

### Grafana

Accessible via ingress at `https://grafana.your-domain.com` or:

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
# Open http://localhost:3000
# Username: admin, Password: from terraform.tfvars
```

### Traefik Dashboard

```bash
kubectl port-forward svc/traefik 9000:9000 -n kube-system
# Open http://localhost:9000/dashboard/
```

### n8n

Accessible via the configured Ingress at `https://automate.your-domain.com`

### CouchDB (Obsidian Sync)

```bash
kubectl port-forward svc/couchdb 9984:5984 -n obsidian
# Open http://localhost:9984
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