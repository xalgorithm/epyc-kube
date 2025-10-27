# Documentation Directory

This directory contains comprehensive documentation for the infrastructure setup and management.

## 📚 Available Documentation

### `REVERSE-PROXY-SETUP.md`
Complete guide for setting up and managing the nginx reverse proxy.

**Contents:**
- Quick setup instructions
- Architecture overview
- Traffic flow explanation
- Monitoring and maintenance
- Troubleshooting guide
- Security features
- High availability options

## 🏗️ Infrastructure Overview

This documentation covers the complete infrastructure setup including:

- **Proxmox VMs**: Three-node Kubernetes cluster
- **K3s Cluster**: Lightweight Kubernetes distribution
- **NFS Storage**: Persistent volume provisioning
- **MetalLB**: Load balancer for bare metal
- **Traefik**: Ingress controller
- **Nginx Reverse Proxy**: External traffic handling
- **Cert-Manager**: SSL certificate automation

## 🔗 Related Resources

- **Scripts**: `../scripts/` - Utility scripts for management
- **Config**: `../config/` - Configuration files
- **Kubernetes**: `../kubernetes/` - Kubernetes manifests
- **Terraform**: `../modules/` - Infrastructure as code

## 📖 Reading Order

For new users, recommended reading order:

1. `REVERSE-PROXY-SETUP.md` - Start here for the complete setup
2. `../scripts/README.md` - Available management scripts
3. Project root `README.md` - Overall project overview

## 🤝 Contributing

When adding new documentation:

- Use clear, descriptive filenames
- Include table of contents for longer documents
- Add cross-references to related files
- Update this README when adding new docs
- Follow markdown best practices