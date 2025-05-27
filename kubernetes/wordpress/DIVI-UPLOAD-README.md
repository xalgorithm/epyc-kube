# Divi Theme Upload Instructions

This directory contains Kubernetes Job configurations for uploading and integrating the Divi WordPress theme into your WordPress installation.

## Prerequisites

- The WordPress deployment is running in your Kubernetes cluster
- You have the Divi.zip theme file downloaded locally
- You have kubectl installed and configured to access your cluster

## Option 1: Using the Automated Script (Recommended)

The easiest way to upload the Divi theme is using the provided shell script:

```bash
# Upload from a local file
./kubernetes/wordpress/upload-divi.sh --file /path/to/your/Divi.zip

# Or upload from a URL
./kubernetes/wordpress/upload-divi.sh --url https://your-download-url/Divi.zip

# Use the ConfigMap-based job (alternative implementation)
./kubernetes/wordpress/upload-divi.sh --file /path/to/your/Divi.zip --configmap
```

The script will handle all the necessary steps and provide helpful progress information.

## Option 2: Using the Basic Job

1. Apply the job configuration:
   ```bash
   kubectl apply -f kubernetes/wordpress/upload-divi-theme-job.yaml
   ```

2. Wait for the pod to be created:
   ```bash
   kubectl get pods -n wordpress -l job-name=wordpress-upload-divi -w
   ```

3. Once the pod is in the Running state, copy the Divi.zip file to the pod:
   ```bash
   kubectl cp /path/to/your/Divi.zip UPLOAD_POD_NAME:/divi/Divi.zip -n wordpress
   ```
   (Replace UPLOAD_POD_NAME with the actual pod name)

4. Monitor the job logs:
   ```bash
   kubectl logs -f UPLOAD_POD_NAME -n wordpress
   ```

5. Wait for the job to complete. You should see "Divi theme installed successfully!" in the logs.

## Option 3: Using the ConfigMap-based Job

1. Apply the ConfigMap and job configuration:
   ```bash
   kubectl apply -f kubernetes/wordpress/upload-divi-theme-configmap.yaml
   kubectl apply -f kubernetes/wordpress/upload-divi-theme-job-configmap.yaml
   ```

2. Wait for the pod to be created:
   ```bash
   kubectl get pods -n wordpress -l job-name=wordpress-upload-divi-configmap -w
   ```

3. Once the pod is in the Running state, copy the Divi.zip file to the pod:
   ```bash
   kubectl cp /path/to/your/Divi.zip UPLOAD_POD_NAME:/divi/Divi.zip -n wordpress
   ```
   (Replace UPLOAD_POD_NAME with the actual pod name)

4. Monitor the job logs:
   ```bash
   kubectl logs -f UPLOAD_POD_NAME -n wordpress
   ```

5. Wait for the job to complete. You should see "Divi theme installed successfully!" in the logs.

## Option 4: Low-Memory Job for Large Theme Files

If your Divi.zip file is very large (>100MB) and causing Out-of-Memory (OOM) issues, use the low-memory variant:

1. Apply the low-memory job configuration:
   ```bash
   kubectl apply -f kubernetes/wordpress/upload-divi-theme-job-lowmem.yaml
   ```

2. Wait for the pod to be created:
   ```bash
   kubectl get pods -n wordpress -l job-name=wordpress-upload-divi-lowmem -w
   ```

3. Once the pod is in the Running state, copy the Divi.zip file to the pod:
   ```bash
   kubectl cp /path/to/your/Divi.zip UPLOAD_POD_NAME:/divi/Divi.zip -n wordpress
   ```

4. Monitor the job logs:
   ```bash
   kubectl logs -f UPLOAD_POD_NAME -n wordpress
   ```

This low-memory variant uses techniques to minimize memory usage during the theme installation process.

## Alternative: Providing a Download URL

If you have a direct download URL for the Divi theme, you can modify the job to download it directly:

1. Edit any of the job files and set the DIVI_URL environment variable:
   ```yaml
   env:
   - name: DIVI_URL
     value: "https://your-download-url/Divi.zip"
   ```

2. Apply the updated job configuration.

## Activate the Theme

After the theme is uploaded, you need to activate it from the WordPress admin panel:

1. Log into your WordPress admin dashboard
2. Navigate to Appearance > Themes
3. Find the Divi theme and click "Activate"

## Troubleshooting

### Out of Memory (OOM) Errors

If you see a pod termination with exit code 137 or the message "command terminated with exit code 137", this indicates an Out of Memory (OOM) error:

1. Use the low-memory job variant:
   ```bash
   kubectl apply -f kubernetes/wordpress/upload-divi-theme-job-lowmem.yaml
   ```

2. If that still fails, try providing a direct download URL instead of copying the file:
   ```bash
   kubectl delete job wordpress-upload-divi-lowmem -n wordpress
   # Edit the job to include the DIVI_URL and reapply
   kubectl apply -f kubernetes/wordpress/upload-divi-theme-job-lowmem.yaml
   ```

3. If all else fails, you may need to install the theme manually by:
   - Extracting the zip file locally
   - Using kubectl cp to copy the extracted files directly to the WordPress pod

### Other Issues

1. Check the logs for error messages:
   ```bash
   kubectl logs UPLOAD_POD_NAME -n wordpress
   ```

2. If there are permission issues, you may need to run the fix-permissions job:
   ```bash
   kubectl apply -f kubernetes/wordpress/fix-permissions-job.yaml
   ```

3. If the unzip operation fails, ensure your Divi.zip file is not corrupted. 