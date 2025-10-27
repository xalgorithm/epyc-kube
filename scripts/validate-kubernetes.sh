#!/bin/bash
set -e

echo "===== Validating Kubernetes manifests ====="
echo

# Counter for valid and invalid files
valid_count=0
invalid_count=0
total_count=0

# Get list of YAML files
yaml_files=$(find kubernetes -name "*.yaml" | sort)

# Process each YAML file
for file in $yaml_files; do
  ((total_count++))
  echo -n "Validating $file... "
  
  if kubectl apply --dry-run=client -f "$file" -o yaml > /dev/null 2>&1; then
    echo "Valid"
    ((valid_count++))
  else
    echo "Invalid"
    ((invalid_count++))
    echo "  Error details:"
    kubectl apply --dry-run=client -f "$file" 2>&1 | sed 's/^/    /'
    echo
  fi
done

echo
echo "===== Validation Summary ====="
echo "Total files validated: $total_count"
echo "Valid manifests: $valid_count"
echo "Invalid manifests: $invalid_count"
echo

# Validate Terraform
echo "===== Validating Terraform configuration ====="
terraform validate

echo
echo "===== Terraform Format Check ====="
terraform fmt -check || terraform fmt

echo
echo "===== Validation completed =====" 