#!/bin/bash

# Test script to generate metrics for the ntfy dashboard
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

TOPICS=("test-topic" "monitoring-alerts" "critical-alerts" "system-updates" "user-notifications")
PRIORITIES=("low" "default" "high" "urgent")
TITLES=("Test Message" "System Alert" "Critical Issue" "Information Update" "User Notification")
MESSAGES=(
  "This is a test message"
  "System CPU usage high"
  "Database connection failed"
  "New update available"
  "Your request has been processed"
)

echo "Generating test data for ntfy metrics..."

# Run for 2 minutes generating random messages
ENDTIME=$(($(date +%s) + 120))

while [ $(date +%s) -lt $ENDTIME ]; do
  # Pick random values
  TOPIC=${TOPICS[$RANDOM % ${#TOPICS[@]}]}
  PRIORITY=${PRIORITIES[$RANDOM % ${#PRIORITIES[@]}]}
  TITLE=${TITLES[$RANDOM % ${#TITLES[@]}]}
  MESSAGE=${MESSAGES[$RANDOM % ${#MESSAGES[@]}]}
  
  echo "Sending to topic: $TOPIC"
  curl -H "Title: $TITLE" \
       -H "Priority: $PRIORITY" \
       -d "$MESSAGE" \
       ${NTFY_URL}/$TOPIC
  
  # Random sleep between 1-5 seconds
  SLEEP_TIME=$((1 + $RANDOM % 5))
  sleep $SLEEP_TIME
done

echo "Test data generation complete."
echo "Check your Grafana dashboard to see the metrics." 