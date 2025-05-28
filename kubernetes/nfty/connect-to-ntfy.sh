#!/bin/bash

# connect-to-ntfy.sh
# Script to securely connect to ntfy service via port-forwarding
# This eliminates the need for public exposure of the ntfy service

set -e

# Configuration
NAMESPACE="monitoring"
HTTP_PORT=8080
METRICS_PORT=9090
SERVICE_NAME="ntfy"

# Help function
show_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Connect to ntfy service via port-forwarding."
  echo ""
  echo "Options:"
  echo "  -h, --help          Show this help message"
  echo "  -p, --port PORT     Local port for ntfy HTTP interface (default: 8080)"
  echo "  -m, --metrics PORT  Local port for ntfy metrics (default: 9090)"
  echo "  -n, --namespace NS  Kubernetes namespace (default: monitoring)"
  echo ""
  echo "Examples:"
  echo "  $0                  Connect with default settings"
  echo "  $0 -p 9000          Use port 9000 for HTTP interface"
  echo "  $0 -m 8000          Use port 8000 for metrics"
  echo ""
  echo "After connecting, ntfy will be available at:"
  echo "  - HTTP API:   http://localhost:$HTTP_PORT"
  echo "  - Metrics:    http://localhost:$METRICS_PORT"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -h|--help)
      show_help
      exit 0
      ;;
    -p|--port)
      HTTP_PORT="$2"
      shift 2
      ;;
    -m|--metrics)
      METRICS_PORT="$2"
      shift 2
      ;;
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

echo "Connecting to ntfy service in namespace $NAMESPACE..."

# Check if the service exists
if ! kubectl get service -n $NAMESPACE $SERVICE_NAME &>/dev/null; then
  echo "Error: Service '$SERVICE_NAME' not found in namespace '$NAMESPACE'"
  exit 1
fi

# Check if ports are already in use
for port in $HTTP_PORT $METRICS_PORT; do
  if lsof -i ":$port" &>/dev/null; then
    echo "Error: Port $port is already in use"
    exit 1
  fi
done

# Start port-forwarding
echo "Starting port-forwarding..."
echo "  - HTTP API:   http://localhost:$HTTP_PORT"
echo "  - Metrics:    http://localhost:$METRICS_PORT"
echo ""
echo "Press Ctrl+C to stop"

# Forward both HTTP and metrics ports
kubectl port-forward -n $NAMESPACE svc/$SERVICE_NAME $HTTP_PORT:80 $METRICS_PORT:9090

# This will never be reached unless port-forwarding fails
echo "Port-forwarding stopped" 