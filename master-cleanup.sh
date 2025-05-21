#!/bin/bash
set -e

echo "===== Starting master cleanup script ====="
echo

# Run the main project cleanup
echo "Running main project cleanup..."
./cleanup.sh

echo
echo "===== WordPress cleanup ====="
echo

# Run the WordPress cleanup
echo "Running WordPress cleanup..."
./kubernetes/wordpress/cleanup.sh

echo
echo "===== Cleanup completed ====="

echo
echo "You may also want to run the existing cleanup script for additional files:"
echo "  ./kubernetes/cleanup-project.sh" 