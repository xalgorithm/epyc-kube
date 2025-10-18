# WordPress on Kubernetes (ethosenv)

This directory contains the Kubernetes manifests and scripts to deploy WordPress in the `ethosenv` namespace with comprehensive migration and fix capabilities.

## 🚀 Quick Start

### **Option 1: Complete Deployment (Recommended)**

```bash
./run-script.sh master-deploy-wordpress
```

This single command will:

- Deploy all Kubernetes resources
- Install WP-CLI
- Migrate content from `../ethosenv/wordpress`
- Fix all URL issues
- Configure SSL and ingress

### **Option 2: Step-by-Step Deployment**

```bash
# 1. Deploy basic WordPress
./run-script.sh deploy-wordpress

# 2. Install WP-CLI
./run-script.sh install-wpcli-existing

# 3. Migrate content
./run-script.sh migrate-wordpress-content-alt

# 4. Fix URLs
./run-script.sh fix-wordpress-urls

# 5. Fix ingress issues
./run-script.sh fix-ingress-issues
```

## 📁 Directory Structure

```
kubernetes/ethosenv-k8s/
├── scripts/                    # All shell scripts
│   ├── master-deploy-wordpress.sh    # Complete deployment
│   ├── deploy-wordpress.sh           # Basic deployment
│   ├── migrate-*.sh                  # Content migration scripts
│   ├── fix-*.sh                      # Fix and repair scripts
│   ├── check-*.sh                    # Diagnostic scripts
│   └── ...
├── wordpress-with-wpcli/       # Custom Docker image files
├── *.yaml                      # Kubernetes manifests
├── run-script.sh              # Script launcher
└── README.md                  # This file
```

## 📋 Available Scripts

### **🚀 Deployment Scripts**

- `master-deploy-wordpress` - **Complete deployment with all fixes**
- `deploy-wordpress` - Basic WordPress deployment
- `quick-start` - Quick deployment guide

### **🔧 Setup & Configuration**

- `install-cert-manager` - Install cert-manager for SSL
- `configure-dns` - DNS configuration guide
- `install-wpcli-existing` - Install WP-CLI in existing container
- `redeploy-wordpress-with-wpcli` - Redeploy with WP-CLI

### **📁 Content Migration**

- `migrate-wordpress-content` - Migrate WordPress files (tar method)
- `migrate-wordpress-content-alt` - **Alternative migration (no tar, recommended)**
- `migrate-wordpress-simple` - Simple migration method
- `migrate-database` - Database migration

### **🔗 URL & Connectivity Fixes**

- `fix-wordpress-urls` - **Fix WordPress URLs (remove :8080, set HTTPS)**
- `fix-ingress-issues` - **Fix ingress connectivity issues**
- `update-wordpress-urls` - Basic URL updates
- `update-wordpress-urls-advanced` - Advanced URL updates with WP-CLI
- `update-wordpress-urls-simple` - Simple URL updates

### **🔍 Diagnostics & Monitoring**

- `diagnose-wordpress` - **Comprehensive WordPress diagnostics**
- `check-ingress-status` - Check ingress and service status
- `check-wordpress-urls` - Check current WordPress URLs
- `check-ssl-status` - Check SSL certificate status
- `verify-deployment` - Verify deployment status
- `monitor-wordpress` - Monitor WordPress deployment

## 🎯 Common Use Cases

### **Deploy from Scratch:**

```bash
./run-script.sh master-deploy-wordpress
```

### **Fix "No Available Server" Error:**

```bash
./run-script.sh fix-ingress-issues
```

### **Fix URLs with :8080 Port:**

```bash
./run-script.sh fix-wordpress-urls
```

### **Diagnose Issues:**

```bash
./run-script.sh diagnose-wordpress
```

### **Migrate Content Only:**

```bash
./run-script.sh migrate-wordpress-content-alt
```

## 📦 Kubernetes Manifests

- `01-namespace.yaml` - Creates the ethosenv namespace
- `02-secrets.yaml` - WordPress and MySQL secrets
- `03-storage.yaml` - Persistent volume claims
- `04-mysql-deployment.yaml` - MySQL database deployment
- `05-wordpress-deployment.yaml` - WordPress application deployment
- `06-ingress.yaml` - Ingress configuration with SSL
- `07-cert-manager-issuer.yaml` - Let's Encrypt certificate issuer
- `08-ssl-certificate.yaml` - SSL certificate configuration

## ⚙️ Configuration

### **Target URL**

- Production URL: `https://ethos.gray-beard.com`
- WordPress Admin: `https://ethos.gray-beard.com/wp-admin`

### **Source Content**

- Expected location: `../ethosenv/wordpress/`
- Contains: themes, plugins, uploads, .htaccess, etc.

### **Database**

- Database: `wordpress`
- User: `wordpress`
- Password: `wordpress_password` (configured in secrets)

## 🔧 Prerequisites

- Kubernetes cluster with ingress controller (Traefik)
- cert-manager for SSL certificates
- kubectl configured to access your cluster
- WordPress content at `../ethosenv/wordpress/`

## 🛠️ Troubleshooting

### **Common Issues:**

1. **"No available server" error:**

   ```bash
   ./run-script.sh fix-ingress-issues
   ```

2. **URLs redirect to :8080:**

   ```bash
   ./run-script.sh fix-wordpress-urls
   ```

3. **WP-CLI not working:**

   ```bash
   ./run-script.sh install-wpcli-existing
   ```

4. **Content not migrated:**

   ```bash
   ./run-script.sh migrate-wordpress-content-alt
   ```

### **Diagnostic Commands:**

```bash
# Full diagnostics
./run-script.sh diagnose-wordpress

# Check specific components
./run-script.sh check-ingress-status
./run-script.sh check-wordpress-urls
./run-script.sh verify-deployment
```

### **Manual Checks:**

```bash
# Check pods
kubectl get pods -n ethosenv

# Check services
kubectl get services -n ethosenv

# Check ingress
kubectl get ingress -n ethosenv

# Port-forward for testing
kubectl port-forward svc/wordpress 8080:80 -n ethosenv
```

## 🔒 Security Notes

- Change default passwords in `02-secrets.yaml`
- Review WordPress security keys
- Configure proper backup procedures
- Monitor for security updates
- SSL certificates are automatically managed by cert-manager

## 🎉 Success Indicators

After successful deployment:

- ✅ Site accessible at `https://ethos.gray-beard.com`
- ✅ WordPress admin at `https://ethos.gray-beard.com/wp-admin`
- ✅ All content migrated from source
- ✅ No URL issues or port redirects
- ✅ SSL certificate working
- ✅ WP-CLI available for management
