# Repository Separation Guide

## Overview

This guide explains how to separate the `epyc` repository into two distinct repositories:

1. **epyc-private** (PRIVATE) - Contains original credentials and sensitive data
2. **epyc-kube** (PUBLIC-SAFE) - Contains sanitized/redacted configuration

## Current State

- **Main branch** (commit cd08082): Contains original credentials, IPs, domains, emails
- **backup-sanitized-20251228 branch** (commit 22a6c0e): Contains sanitized content

## Quick Start

### Step 1: Create GitHub Repository

Go to: https://github.com/new

**Repository Settings:**
- Name: `epyc-private`
- Description: `Private infrastructure configuration`
- Visibility: **PRIVATE** ⚠️ (CRITICAL!)
- Do NOT initialize with README
- Do NOT add .gitignore
- Do NOT add license

Click "Create repository"

### Step 2: Run Separation Script

```bash
./separate-repositories.sh
```

That's it! The script handles everything else automatically.

## What the Script Does

### Phase 1: Push to epyc-private
- Checks out current main branch (cd08082)
- Pushes to `git@github.com:xalgorithm/epyc-private.git`
- Contains: Original passwords, credentials, IPs, domains

### Phase 2: Push to epyc-kube
- Checks out `backup-sanitized-20251228` branch
- Creates `main-sanitized` branch
- Pushes to `git@github.com:xalgorithm/epyc-kube.git`
- Contains: Redacted/sanitized content

### Phase 3: Set Up Tracking
- `main` branch tracks `epyc-private/main`
- `main-sanitized` branch tracks `epyc-kube/main`

## Final Repository Structure

### epyc-private (PRIVATE Repository)
```
URL: https://github.com/xalgorithm/epyc-private
Branch: main
Content:
  ✓ Original passwords (Pr1amsf0lly!)
  ✓ Original emails (x.algorithm@gmail.com, find.me@xalg.im)
  ✓ Original IPs (107.172.99.x, 198.55.108.8/29)
  ✓ Original domains (*.xalg.im, kampfzwerg.me)
  ✓ Credential files (grafana-admin-credentials.yaml, etc.)

Local branch: main
```

### epyc-kube (PUBLIC-SAFE Repository)
```
URL: https://github.com/xalgorithm/epyc-kube
Branch: main
Content:
  ✓ Redacted passwords (changeme123)
  ✓ Redacted emails (admin@example.com)
  ✓ Redacted IPs (10.0.1.x, 10.0.2.0/29)
  ✓ Redacted domains (*.gray-beard.com)
  ✓ No credential files in history

Local branch: main-sanitized
```

## Daily Workflow

### Working with Private Content
```bash
# Switch to private branch
git checkout main

# Make changes
# ...

# Push to private repository
git push epyc-private main
```

### Working with Public Content
```bash
# Switch to sanitized branch
git checkout main-sanitized

# Make changes
# ...

# Push to public repository
git push epyc-kube main-sanitized:main
```

### Syncing Changes Between Repositories

If you make infrastructure changes in the private repo that need to be reflected in the public repo:

```bash
# On private branch
git checkout main
# Make changes, commit

# Apply same changes to sanitized branch
git checkout main-sanitized
# Manually apply changes with redacted credentials
# Commit

# Push both
git checkout main && git push epyc-private main
git checkout main-sanitized && git push epyc-kube main-sanitized:main
```

## Remote Configuration

After separation, your remotes will be:

```bash
$ git remote -v
epyc-kube     git@github.com:xalgorithm/epyc-kube.git (fetch)
epyc-kube     git@github.com:xalgorithm/epyc-kube.git (push)
epyc-private  git@github.com:xalgorithm/epyc-private.git (fetch)
epyc-private  git@github.com:xalgorithm/epyc-private.git (push)
origin        git@github.com:xalgorithm/epyc-kube.git (fetch)
origin        git@github.com:xalgorithm/epyc-kube.git (push)
```

## Branch Configuration

```bash
$ git branch -vv
* main             cd08082 [epyc-private/main] docs: comprehensive documentation...
  main-sanitized   22a6c0e [epyc-kube/main] chore: remove orphaned submodule...
```

## Security Considerations

### epyc-private Repository
- **MUST be PRIVATE** at all times
- Contains active/historical credentials
- Restrict access to essential personnel only
- Enable GitHub secret scanning
- Enable GitHub dependency alerts
- Consider rotating exposed credentials

### epyc-kube Repository
- Can be made PUBLIC if desired
- All sensitive data has been redacted
- Safe for portfolios, documentation, sharing
- Still recommend keeping PRIVATE unless needed public

## Troubleshooting

### Repository Creation Failed
```bash
# Verify you have access
ssh -T git@github.com

# Check if repository exists
curl https://api.github.com/repos/xalgorithm/epyc-private

# If it doesn't exist, create it via GitHub web interface
```

### Push Failed
```bash
# Check remotes are configured
git remote -v

# Update remote URL if needed
git remote set-url epyc-private git@github.com:xalgorithm/epyc-private.git

# Force push if necessary
git push --force epyc-private main
```

### Wrong Branch Pushed
```bash
# Delete incorrect branch from remote
git push epyc-private :main

# Push correct branch
git checkout main
git push epyc-private main
```

## Alternative: Manual Separation

If you prefer to do it manually:

### Push to epyc-private
```bash
git checkout main
git remote add epyc-private git@github.com:xalgorithm/epyc-private.git
git push -u epyc-private main
```

### Push to epyc-kube
```bash
git checkout backup-sanitized-20251228
git checkout -b main-sanitized
git push epyc-kube main-sanitized:main --force
git push origin main-sanitized:main --force
```

### Set Up Tracking
```bash
git checkout main
git branch --set-upstream-to=epyc-private/main main

git checkout main-sanitized
git branch --set-upstream-to=epyc-kube/main main-sanitized
```

## Verification

After separation, verify:

```bash
# Check epyc-private has unsanitized content
git checkout main
cat kubernetes/grafana/grafana-admin-credentials.yaml
# Should see: UHIxYW1zZjBsbHkh (Pr1amsf0lly!)

# Check epyc-kube has sanitized content
git checkout main-sanitized
git log -1
# Should be commit 22a6c0e (sanitized)
```

## Backup

A backup of the sanitized state exists at:
- Branch: `backup-sanitized-20251228`
- Commit: 22a6c0e

This can be deleted after successful separation.

## Summary

| Repository | Visibility | Branch | Content | Use Case |
|------------|-----------|--------|---------|----------|
| epyc-private | PRIVATE | main | Original | Internal infrastructure work |
| epyc-kube | PUBLIC-SAFE | main | Sanitized | Documentation, sharing, portfolio |

---

**Created:** December 28, 2025  
**Script:** `separate-repositories.sh`  
**Status:** Ready to execute

