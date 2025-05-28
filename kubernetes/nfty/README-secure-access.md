# Secure ntfy Access

## Overview

The ntfy service has been configured for secure, private access only. Instead of exposing the service via an Ingress, it is now only accessible via Kubernetes port-forwarding. This change enhances security by:

1. Removing public exposure of the notification service
2. Eliminating the attack surface that a public endpoint creates
3. Requiring kubectl access to the cluster to interact with ntfy

## Accessing ntfy

To access the ntfy service, use the provided script:

```bash
./connect-to-ntfy.sh
```

This will:
- Create a secure tunnel to the ntfy service in the Kubernetes cluster
- Forward the ntfy HTTP interface to `http://localhost:8080`
- Forward the ntfy metrics endpoint to `http://localhost:9090`

## Usage Options

The script provides several customization options:

```bash
Usage: ./connect-to-ntfy.sh [options]

Connect to ntfy service via port-forwarding.

Options:
  -h, --help          Show this help message
  -p, --port PORT     Local port for ntfy HTTP interface (default: 8080)
  -m, --metrics PORT  Local port for ntfy metrics (default: 9090)
  -n, --namespace NS  Kubernetes namespace (default: monitoring)

Examples:
  ./connect-to-ntfy.sh                  Connect with default settings
  ./connect-to-ntfy.sh -p 9000          Use port 9000 for HTTP interface
  ./connect-to-ntfy.sh -m 8000          Use port 8000 for metrics
```

## Using ntfy

Once connected, you can:

1. Send notifications using `curl`:
   ```bash
   curl -H "Title: Test Notification" -d "This is a test" http://localhost:8080/topic-name
   ```

2. Subscribe to topics via the web interface at `http://localhost:8080`

3. View metrics at `http://localhost:9090/metrics`

## Integration with Grafana

If you're using ntfy with Grafana for notifications, update the following files to use the local address instead of the previously public URL:

- Update notification scripts to use `http://ntfy.monitoring.svc.cluster.local` (Kubernetes service DNS) instead of the public URL
- For testing from outside the cluster, run the port-forwarding script and use `http://localhost:8080`

## Security Considerations

- The port-forwarding connection is only active while the script is running
- The connection is only accessible from your local machine
- For permanent secure access, consider setting up a VPN to your Kubernetes cluster 