# Scripts Directory

This directory contains utility scripts for managing the Kubernetes cluster and services.

## 📁 Directory Structure

All scripts are organized in this central location. Related scripts are grouped by function:
- **Infrastructure**: Setup and configuration scripts
- **Diagnostic**: Health checks and troubleshooting
- **Backup**: Data backup and restoration
- **Cleanup**: Resource removal and migration

## 🔧 Infrastructure Scripts

### `setup-reverse-proxy.sh`
Sets up nginx reverse proxy on the control plane node to handle incoming traffic on standard ports (80/443).

**Usage:**
```bash
./setup-reverse-proxy.sh
```

**What it does:**
- Installs nginx
- Configures reverse proxy to forward to Kubernetes NodePorts
- Sets up SSL with self-signed certificates
- Configures security headers

### `setup-letsencrypt.sh`
Configures Let's Encrypt SSL certificates for all domains.

**Usage:**
```bash
./setup-letsencrypt.sh
```

**Prerequisites:**
- DNS must be pointing to the server
- Reverse proxy must be set up first

## ✅ Verification Scripts

### `verify-root-cleanliness.sh`
Verifies that the root directory contains only allowed files per the project organization requirements.

**Usage:**
```bash
./scripts/verify-root-cleanliness.sh
```

**What it checks:**
- Only allowed file types exist in root (*.tf, *.tfvars, README.md, .gitignore, etc.)
- Reports any violations with suggested actions
- Returns exit code 0 on success, 1 on violations

**Validates:** Requirements 1.1, 1.2, 1.3 (Root Directory Cleanliness)

## 🔍 Diagnostic Scripts

### `test-all-domains.sh`
Comprehensive connectivity test for all configured domains.

**Usage:**
```bash
./test-all-domains.sh
```

**Tests:**
- DNS resolution
- HTTP to HTTPS redirect
- HTTPS response codes
- SSL certificate validation

### `check-services.sh`
Health check script for all Kubernetes services.

**Usage:**
```bash
./check-services.sh
```

**Checks:**
- Service HTTP responses
- Kubernetes NodePort connectivity
- Nginx status and logs

### `fix-nfs-connectivity.sh`
Diagnoses NFS connectivity issues between Kubernetes nodes and NFS server.

**Usage:**
```bash
./fix-nfs-connectivity.sh
```

**Tests:**
- Network connectivity to NFS server
- NFS port accessibility
- Mount capability testing

## 🗑️ Cleanup Scripts

### `remove-airflow.sh`
Completely removes Airflow and all its dependencies from the cluster.

**Usage:**
```bash
./remove-airflow.sh
```

**⚠️ Warning:** This permanently deletes all Airflow data and cannot be undone.

### `migrate-to-local-storage.sh`
Migrates services from NFS storage to local storage.

**Usage:**
```bash
./migrate-to-local-storage.sh
```

**⚠️ Warning:** This will lose all existing data stored on NFS.

## 📋 Usage Notes

### Making Scripts Executable
```bash
chmod +x scripts/*.sh
```

### Running from Root Directory
```bash
# From the project root
./scripts/test-all-domains.sh
```

### SSH Configuration
Most scripts expect an SSH config file in the project root (`ssh_config`) for accessing Kubernetes nodes.

### IDE Configuration
IDE configuration files (`.cursorrules`, `epyc.code-workspace`) are located in `.vscode/` directory.

## 🔐 Security Considerations

- Scripts that modify infrastructure should be reviewed before execution
- Always test in a non-production environment first
- Scripts with data deletion warnings require careful consideration
- Ensure proper backup procedures before running destructive operations

## 📝 Script Dependencies

- `kubectl` with valid kubeconfig
- SSH access to Kubernetes nodes
- `curl` for connectivity testing
- `openssl` for SSL testing
- `helm` for some operations