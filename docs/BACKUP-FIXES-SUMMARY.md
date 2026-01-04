# Backup System Fixes Summary

## Problem Analysis

The backup system was experiencing two persistent failure modes:

### 1. NFS Mount Failures (Exit Status 32)

**Affected Pods:**
- `backup-cleanup-*`
- `data-backup-*`

**Root Cause:**
The backup CronJobs were configured to mount NFS directly using:
```yaml
volumes:
  - name: backup-storage
    nfs:
      server: 192.168.0.3
      path: /mnt/red-nas/k8s-backups
```

**Issues:**
- The NFS server `192.168.0.3` is not accessible from the cluster nodes
- The cluster's working NFS provisioner uses `10.0.1.210:/data`
- Direct NFS mounts bypass the cluster's NFS provisioner infrastructure
- Exit status 32 indicates "mount failed" due to connectivity or permission issues

### 2. Node Affinity Mismatch

**Affected Pods:**
- `etcd-backup-*`

**Root Cause:**
The etcd-backup CronJob was configured with:
```yaml
nodeSelector:
  node-role.kubernetes.io/control-plane: ""
```

But the actual control plane node has:
```yaml
labels:
  node-role.kubernetes.io/control-plane: "true"
```

**Issue:**
The node selector was looking for nodes where the label has an empty value, but the actual label has the value `"true"`, causing the scheduler to find no matching nodes.

## Solution

### Fix 1: Use PVC Instead of Direct NFS Mount

Changed all backup jobs to use a PersistentVolumeClaim that leverages the working NFS provisioner:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-storage-pvc
  namespace: backup
spec:
  accessModes:
    - ReadWriteMany  # Multiple backup jobs need access
  storageClassName: nfs-client  # Use the working NFS provisioner
  resources:
    requests:
      storage: 100Gi
```

**Benefits:**
- Uses the proven NFS infrastructure (`10.0.1.210:/data`)
- Automatic provisioning and management
- Consistent with other workloads in the cluster
- Better error handling and monitoring

### Fix 2: Correct Node Selector

Updated the etcd-backup CronJob to match the actual node labels:

```yaml
nodeSelector:
  node-role.kubernetes.io/control-plane: "true"
tolerations:
- key: node-role.kubernetes.io/control-plane
  operator: Exists
  effect: NoSchedule
- key: node-role.kubernetes.io/master
  operator: Exists
  effect: NoSchedule
```

**Benefits:**
- Correctly matches the control plane node (gimli)
- Includes tolerations for both possible taint keys
- Allows the etcd-backup pod to be scheduled

## Implementation

### Files Created

1. **`kubernetes/backup-fixes.yaml`**
   - Contains all the fixed CronJob definitions
   - Includes the new PVC definition
   - Ready to apply with kubectl

2. **`kubernetes/apply-backup-fixes.sh`**
   - Automated script to apply fixes
   - Includes validation and verification steps
   - Provides helpful troubleshooting output

3. **`docs/BACKUP-FIXES-SUMMARY.md`** (this file)
   - Complete documentation of the problem and solution
   - Reference for future troubleshooting

### Application Steps

```bash
cd /Users/xalg/dev/terraform/epyc/kubernetes
./apply-backup-fixes.sh
```

The script will:
1. Clean up existing failed jobs
2. Create the backup storage PVC
3. Update all CronJobs with the fixes
4. Verify the changes
5. Provide monitoring commands

## Verification

### Check PVC Status
```bash
kubectl get pvc -n backup backup-storage-pvc
```

Expected output:
```
NAME                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
backup-storage-pvc   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   100Gi      RWX            nfs-client     1m
```

### Check CronJobs
```bash
kubectl get cronjobs -n backup
```

Expected output:
```
NAME             SCHEDULE    SUSPEND   ACTIVE   LAST SCHEDULE   AGE
backup-cleanup   0 4 * * 0   False     0        44h             64d
data-backup      0 3 * * *   False     0        21h             64d
etcd-backup      0 2 * * *   False     0        22h             64d
```

### Monitor Next Backup Run
```bash
# Watch for new backup pods
kubectl get pods -n backup -w

# Check logs when a pod starts
kubectl logs -n backup -l app=data-backup --tail=50 -f
```

## Backup Schedule

| Job | Schedule | Purpose | Storage Path |
|-----|----------|---------|--------------|
| **etcd-backup** | Daily at 2:00 AM | Backup Kubernetes etcd database | `/backup/etcd` |
| **data-backup** | Daily at 3:00 AM | Backup application data | `/backup/data` |
| **backup-cleanup** | Weekly on Sunday at 4:00 AM | Clean up old backups | `/backup` |

## NFS Infrastructure

### Working NFS Configuration

The cluster uses an NFS provisioner with the following configuration:

- **NFS Server:** `10.0.1.210`
- **NFS Path:** `/data`
- **Provisioner:** `cluster.local/nfs-subdir-external-provisioner`
- **StorageClass:** `nfs-client`

This is deployed via Helm in the `nfs-provisioner` namespace and is used successfully by:
- All WordPress sites (ethosenv, kampfzwerg, zali)
- Keycloak
- Obsidian/CouchDB
- n8n
- Vault
- ActivePieces
- Nozyu

### Why Direct NFS Mount Failed

The backup jobs were trying to use a different NFS server (`192.168.0.3`) that:
- Is not accessible from the cluster nodes (107.172.99.x)
- May be a local network address
- Was not properly configured or exported
- Bypassed the cluster's NFS provisioner infrastructure

## Troubleshooting

### If PVC Doesn't Bind

Check the NFS provisioner status:
```bash
kubectl get pods -n nfs-provisioner
kubectl logs -n nfs-provisioner -l app=nfs-subdir-external-provisioner
```

### If etcd-backup Still Fails to Schedule

Verify node labels:
```bash
kubectl get nodes --show-labels | grep control-plane
```

Check if the control plane node is ready:
```bash
kubectl get nodes gimli -o wide
```

### If Backup Jobs Fail

Check pod events:
```bash
kubectl describe pod -n backup <pod-name>
```

Check backup logs:
```bash
kubectl logs -n backup <pod-name>
```

Check PVC mount:
```bash
kubectl exec -n backup <pod-name> -- df -h /backup
```

## Related Files

- **NFS Provisioner:** `kubernetes/nfs-provisioner.yaml`
- **Backup Scripts:** ConfigMap `backup-scripts` in namespace `backup`
- **Service Account:** `backup` in namespace `backup`
- **Kubeconfig Secret:** `backup-kubeconfig` in namespace `backup`

## Future Improvements

1. **Monitoring Integration**
   - Add Prometheus metrics for backup success/failure
   - Create Grafana dashboard for backup status
   - Set up alerts for backup failures

2. **Backup Verification**
   - Add automated restore tests
   - Implement backup integrity checks
   - Create backup size tracking

3. **Documentation**
   - Document backup restore procedures
   - Create runbook for backup failures
   - Add backup retention policy documentation

4. **Infrastructure**
   - Consider using Velero for cluster backups
   - Implement off-site backup replication
   - Add backup encryption

## References

- [Kubernetes CronJobs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
- [NFS Subdir External Provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner)
- [Node Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [PersistentVolumeClaims](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

