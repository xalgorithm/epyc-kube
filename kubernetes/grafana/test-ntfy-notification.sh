#!/bin/bash

# Test script for ntfy notifications with different formats
# This script requires the ntfy port-forwarding to be active
# Run ./connect-to-ntfy.sh in another terminal first

# Default ntfy URL (using port-forwarding)
NTFY_URL=${NTFY_URL:-"http://localhost:8080"}

# Check if ntfy is accessible
if ! curl -s --connect-timeout 3 ${NTFY_URL} > /dev/null; then
  echo "Error: Cannot connect to ntfy at ${NTFY_URL}"
  echo "Please make sure port-forwarding is active by running:"
  echo "  ./connect-to-ntfy.sh"
  exit 1
fi

# Regular notification
echo "Sending regular notification to monitoring-alerts..."
curl -d "Regular monitoring alert from Grafana" \
     ${NTFY_URL}/monitoring-alerts

sleep 2

# Notification with title and priority
echo "Sending notification with title and priority..."
curl -H "Title: CPU Usage Alert" \
     -H "Priority: high" \
     -d "CPU usage is above 90% on server-01" \
     ${NTFY_URL}/monitoring-alerts

sleep 2

# Critical notification with all formatting
echo "Sending critical notification with full formatting..."
curl -H "Title: CRITICAL: Database Down" \
     -H "Priority: urgent" \
     -H "Tags: critical,database,alert" \
     -H "Click: https://grafana.gray-beard.com/d/some-dashboard" \
     -d "The production database is not responding! Immediate action required." \
     ${NTFY_URL}/critical-alerts

sleep 2

# Notification with emoji and formatting
echo "Sending formatted notification with emoji..."
curl -H "Title: 🔥 Service Degraded" \
     -H "Priority: high" \
     -H "Tags: warning,service" \
     -d "Service response time is degraded:
- API: 500ms (normal: <100ms)
- Database: 300ms (normal: <50ms)
- Cache: OK

Check scaling settings." \
     ${NTFY_URL}/monitoring-alerts

echo "All test notifications sent."
echo "Check your ntfy app or visit the following URLs in your browser:"
echo "- ${NTFY_URL}/monitoring-alerts"
echo "- ${NTFY_URL}/critical-alerts" 