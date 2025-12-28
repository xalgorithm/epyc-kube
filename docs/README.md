# Documentation Directory

This directory contains comprehensive documentation for the infrastructure setup and management.

> 📖 **New Here?** Start with the [main README](../README.md) for a complete overview, then return here for detailed guides.

## 📚 Available Documentation

### Infrastructure Setup & Configuration

#### [`REVERSE-PROXY-SETUP.md`](REVERSE-PROXY-SETUP.md)
Complete guide for setting up and managing the nginx reverse proxy.

**Contents:**
- Quick setup instructions with automation scripts
- Architecture overview and traffic flow
- Load balancing across Kubernetes nodes
- Monitoring and maintenance procedures
- Troubleshooting common issues
- Security features (HSTS, modern TLS)
- High availability options

**Related:**
- Configuration files: [`../config/nginx/`](../config/nginx/)
- Setup script: [`../scripts/setup-reverse-proxy.sh`](../scripts/)

---

#### [`network-bridge.md`](network-bridge.md)
Secure WireGuard VPN bridge between colocation and home network.

**Contents:**
- WireGuard configuration for both endpoints
- Security measures and firewall rules
- Tailscale backup connectivity
- Network diagram and topology
- Testing and troubleshooting procedures

**Related:**
- Setup script: [`../scripts/setup-colo-wireguard.sh`](../scripts/)
- Checklist: [`network-bridge-checklist.md`](network-bridge-checklist.md)
- OPNsense guide: [`opnsense-wireguard-setup.md`](opnsense-wireguard-setup.md)

---

#### [`opnsense-wireguard-setup.md`](opnsense-wireguard-setup.md)
Step-by-step OPNsense WireGuard configuration guide.

**Contents:**
- Plugin installation
- Local server configuration
- Peer (colocation server) setup
- Interface assignment
- Firewall rules configuration

**Related:**
- Network bridge overview: [`network-bridge.md`](network-bridge.md)
- Deployment checklist: [`network-bridge-checklist.md`](network-bridge-checklist.md)

---

#### [`proxmox-metallb-subnet-configuration.md`](proxmox-metallb-subnet-configuration.md)
Proxmox network configuration for MetalLB LoadBalancer subnet.

**Contents:**
- Network bridge configuration
- Routing setup for MetalLB subnet (10.0.2.8/29)
- Firewall configuration
- Troubleshooting connectivity issues
- Network topology diagrams

**Related:**
- MetalLB configs: [`../kubernetes/metallb-configurations/`](../kubernetes/metallb-configurations/)
- Traefik fix: [`traefik-external-connectivity-fix.md`](traefik-external-connectivity-fix.md)

---

#### [`traefik-external-connectivity-fix.md`](traefik-external-connectivity-fix.md)
Troubleshooting external HTTP/HTTPS connectivity to Traefik LoadBalancer.

**Contents:**
- Problem diagnosis and root cause analysis
- Required firewall rules for MetalLB subnet
- Automated fix scripts
- Verification procedures
- Network architecture diagrams

**Related:**
- Fix script: [`../scripts/fix-external-traefik-connectivity.sh`](../scripts/)
- Proxmox config: [`proxmox-metallb-subnet-configuration.md`](proxmox-metallb-subnet-configuration.md)

---

#### [`network-bridge-checklist.md`](network-bridge-checklist.md)
Complete deployment checklist for VPN network bridge.

**Contents:**
- Pre-deployment preparation
- Phase-by-phase deployment steps
- Testing procedures for primary and backup connections
- Failover testing
- Post-deployment tasks
- Security verification
- Rollback plan

**Related:**
- Network bridge guide: [`network-bridge.md`](network-bridge.md)
- OPNsense setup: [`opnsense-wireguard-setup.md`](opnsense-wireguard-setup.md)

---

### Project Organization & Updates

#### [`ORGANIZATION-SUMMARY.md`](ORGANIZATION-SUMMARY.md)
Summary of project file organization and cleanup performed.

**Contents:**
- Files organized by category
- Directory READMEs added
- Script updates and path corrections
- Benefits of the new organization

---

#### [`GIT-CLEANUP-SUMMARY.md`](GIT-CLEANUP-SUMMARY.md)
Git history cleanup and repository optimization.

**Contents:**
- Files removed from git history
- Cleanup procedures used
- Prevention measures (.gitignore)
- Repository size optimization
- Best practices going forward

---

#### [`DOCUMENTATION-UPDATE-SUMMARY.md`](DOCUMENTATION-UPDATE-SUMMARY.md)
Comprehensive documentation update summary (December 2025).

**Contents:**
- Complete codebase analysis results
- 15+ applications discovered and documented
- Documentation coverage improvements (+400% increase)
- Cross-referencing and interlinking updates
- Navigation improvements across all docs
- Quality metrics and recommendations

---

## 🏗️ Infrastructure Overview

This documentation covers the complete infrastructure setup including:

### Core Infrastructure
- **Proxmox VMs**: Three-node Kubernetes cluster (gimli, legolas, aragorn)
- **K3s Cluster**: Lightweight Kubernetes distribution
- **NFS Storage**: Persistent volume provisioning
- **MetalLB**: Load balancer for bare metal (IP pool: 10.0.2.8/29)
- **Traefik**: Ingress controller with automatic routing
- **Nginx Reverse Proxy**: External traffic handling on ports 80/443
- **Cert-Manager**: Automated SSL certificate management

### Security & Identity
- **HashiCorp Vault**: Secrets management ([kubernetes/vault/](../kubernetes/vault/))
- **Keycloak**: Single Sign-On authentication ([kubernetes/keycloak/](../kubernetes/keycloak/))
- **Let's Encrypt**: Automated SSL certificates

### Applications
- **WordPress Sites**: ethos.gray-beard.com, kampfzwerg.gray-beard.com
- **Workflow Automation**: n8n, Activepieces
- **Monitoring**: Prometheus, Grafana, Loki, Tempo
- **Obsidian Sync**: Self-hosted note synchronization
- **ntfy**: Push notification service

## 🔗 Related Resources

### Scripts & Automation
- **[Scripts Directory](../scripts/)** - 50+ management and utility scripts
  - Backup automation
  - Setup and configuration
  - Diagnostic and repair tools
  - Migration utilities

### Configuration Files
- **[Config Directory](../config/)** - Configuration files
  - Nginx reverse proxy configs
  - SSL/TLS parameters
  - Security headers
  - K3s cluster configuration

### Kubernetes Manifests
- **[Kubernetes Directory](../kubernetes/)** - Application manifests
  - Application deployments
  - Monitoring stack
  - MetalLB and Traefik configs

### Infrastructure as Code
- **[Terraform Modules](../modules/)** - Infrastructure modules
  - Proxmox VM provisioning
  - Kubernetes infrastructure
  - Monitoring stack
  - Certificate management

### Backups
- **[Backup Directory](../backups/)** - Backup system
  - WordPress site backups
  - Database dumps
  - Backup verification

## 📖 Reading Order

### For New Users

1. **[Main README](../README.md)** - Project overview and capabilities
2. **Infrastructure Setup**:
   - [`proxmox-metallb-subnet-configuration.md`](proxmox-metallb-subnet-configuration.md) - Network foundation
   - [`REVERSE-PROXY-SETUP.md`](REVERSE-PROXY-SETUP.md) - External access
3. **Optional VPN Bridge**:
   - [`network-bridge.md`](network-bridge.md) - VPN setup overview
   - [`network-bridge-checklist.md`](network-bridge-checklist.md) - Deployment steps
   - [`opnsense-wireguard-setup.md`](opnsense-wireguard-setup.md) - OPNsense configuration
4. **Troubleshooting**:
   - [`traefik-external-connectivity-fix.md`](traefik-external-connectivity-fix.md) - Connectivity issues
5. **Management**:
   - [`../scripts/README.md`](../scripts/README.md) - Available scripts and tools

### For Application Deployment

1. Review [application-specific README files](../kubernetes/)
2. Check [monitoring setup guide](../kubernetes/README-monitoring.md)
3. Configure [secrets with Vault](../kubernetes/vault/README.md)
4. Set up [SSO with Keycloak](../kubernetes/keycloak/README.md)

### For Backup & Recovery

1. **[Backup System Overview](../backups/README.md)** - Backup architecture
2. Backup scripts in [`../scripts/`](../scripts/) directory
3. Verification procedures

## 🎯 Quick Reference

### Common Tasks

| Task | Documentation | Script |
|------|---------------|--------|
| Setup reverse proxy | [REVERSE-PROXY-SETUP.md](REVERSE-PROXY-SETUP.md) | `../scripts/setup-reverse-proxy.sh` |
| Configure VPN bridge | [network-bridge.md](network-bridge.md) | `../scripts/setup-colo-wireguard.sh` |
| Fix Traefik connectivity | [traefik-external-connectivity-fix.md](traefik-external-connectivity-fix.md) | `../scripts/fix-external-traefik-connectivity.sh` |
| Backup WordPress sites | [../backups/README.md](../backups/README.md) | `../scripts/backup-all-sites.sh` |
| Test all services | [../scripts/README.md](../scripts/README.md) | `../scripts/test-all-domains.sh` |

### Service-Specific Docs

| Service | Documentation Location |
|---------|----------------------|
| Vault | [`../kubernetes/vault/README.md`](../kubernetes/vault/README.md) |
| Keycloak | [`../kubernetes/keycloak/README.md`](../kubernetes/keycloak/README.md) |
| Activepieces | [`../kubernetes/activepieces/README.md`](../kubernetes/activepieces/README.md) |
| Obsidian | [`../kubernetes/obsidian/README.md`](../kubernetes/obsidian/README.md) |
| WordPress (ethos) | [`../kubernetes/ethosenv-k8s/README.md`](../kubernetes/ethosenv-k8s/README.md) |
| Monitoring | [`../kubernetes/README-monitoring.md`](../kubernetes/README-monitoring.md) |

## 🤝 Contributing

When adding new documentation:

- Use clear, descriptive filenames (kebab-case.md)
- Include table of contents for longer documents
- Add cross-references to related files using relative links
- Update this README when adding new docs
- Follow markdown best practices
- Include code examples where appropriate
- Add diagrams for complex architectures
- Link to relevant scripts and configuration files

### Documentation Template

```markdown
# Title

Brief description of what this document covers.

**Related Documentation:**
- [Related Doc 1](path/to/doc1.md)
- [Related Doc 2](path/to/doc2.md)

**Related Resources:**
- Scripts: ../scripts/relevant-script.sh
- Configs: ../config/relevant-config/

## Contents
[Table of contents]

## Sections
[Main content]
```