# WordPress Kubernetes Sync Scripts

This directory contains scripts for synchronizing WordPress files between your Kubernetes deployment and a local Git repository.

## Scripts

### `wordpress-sync.sh`

This script pulls WordPress files from your Kubernetes pod to a local Git repository.

**Usage:**
```bash
./scripts/wordpress-sync.sh
```

**What it does:**
1. Creates a local Git repository at `./wordpress-site/` if it doesn't exist
2. Backs up current local files before synchronizing
3. Copies all WordPress files from the pod to the local repository
4. Creates a sanitized wp-config-example.php (with sensitive information removed)
5. Commits all changes to the Git repository

### `wordpress-deploy.sh`

This script pushes WordPress files from your local Git repository back to the Kubernetes pod.

**Usage:**
```bash
./scripts/wordpress-deploy.sh
```

**What it does:**
1. Creates a backup of the current WordPress files in the pod
2. Optionally downloads the backup locally
3. Deploys files from the local repository to the pod
4. Preserves the existing wp-config.php if it's not in the local repo
5. Fixes permissions on the deployed files

## Workflow for WordPress Development

1. **Initial Setup:**
   ```bash
   # Initialize the local repository with current WordPress files
   ./scripts/wordpress-sync.sh
   
   # Create a GitHub repository for your WordPress files
   # Then push your local repository to GitHub
   cd wordpress-site
   git remote add origin https://github.com/yourusername/your-wordpress-repo.git
   git push -u origin main
   ```

2. **Development Workflow:**
   ```bash
   # Pull the latest changes from the pod
   ./scripts/wordpress-sync.sh
   
   # Make and test changes locally
   # ...
   
   # Commit your changes
   cd wordpress-site
   git add .
   git commit -m "Description of changes"
   
   # Push to GitHub
   git push origin main
   
   # Deploy changes to the pod
   cd ..
   ./scripts/wordpress-deploy.sh
   ```

3. **Automation (Optional):**
   ```bash
   # Add a cron job to automatically sync WordPress files daily
   crontab -e
   
   # Add this line to run sync daily at 2 AM
   0 2 * * * cd /path/to/epyc2 && ./scripts/wordpress-sync.sh >> /path/to/log/wordpress-sync.log 2>&1
   ```

## Notes

- These scripts assume that you have `kubectl` configured with access to your Kubernetes cluster
- The WordPress pod must be running and accessible
- The WordPress deployment must be in the `wordpress` namespace
- The pod must have a label `app=wordpress` to be found by the scripts 