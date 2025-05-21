#!/bin/bash
set -e

echo "Organizing diagram files..."

# Create a dedicated directory for diagrams
mkdir -p docs/diagrams

# Files to move to docs/diagrams/
DIAGRAM_FILES=(
  "kubernetes-services-diagram.png"
  "services-diagram.dot"
  "services-diagram.mmd"
)

# Move the diagram files
for file in "${DIAGRAM_FILES[@]}"; do
  if [ -f "$file" ]; then
    echo "Moving $file to docs/diagrams/"
    mv "$file" "docs/diagrams/"
  else
    echo "File not found: $file"
  fi
done

echo "Diagram organization completed!" 