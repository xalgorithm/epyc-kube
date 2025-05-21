#!/bin/bash
set -e

echo "===== Starting project organization ====="
echo

# Run file organization
echo "Running file organization..."
./organize-files.sh

echo
echo "===== Organizing diagrams ====="
echo

# Run diagram organization
echo "Running diagram organization..."
./organize-diagrams.sh

echo
echo "===== Organization completed ====="
echo

echo "Project structure has been organized. Here's a summary of what was done:"
echo "1. Grafana files moved to kubernetes/grafana/"
echo "2. Prometheus files moved to kubernetes/prometheus/"
echo "3. Loki files moved to kubernetes/loki/"
echo "4. Diagram files moved to docs/diagrams/"
echo "5. Grafana backup files moved to kubernetes/grafana/backup/" 