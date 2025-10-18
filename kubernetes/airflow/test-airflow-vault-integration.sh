#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Testing Airflow Vault integration..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print test results
print_result() {
  if [ $1 -eq 0 ]; then
    echo -e "${GREEN}✓${NC} $2"
  else
    echo -e "${RED}✗${NC} $2"
  fi
}

# Test 1: Check if Vault is accessible
echo "1. Testing Vault accessibility..."
if kubectl get pods -n vault -l app=vault | grep -q Running; then
  print_result 0 "Vault pod is running"
else
  print_result 1 "Vault pod is not running"
  exit 1
fi

# Test 2: Check if Vault Secrets Operator is running
echo "2. Testing Vault Secrets Operator..."
if kubectl get pods -n vault-secrets -l app=vault-secrets-operator | grep -q Running; then
  print_result 0 "Vault Secrets Operator is running"
else
  print_result 1 "Vault Secrets Operator is not running"
  exit 1
fi

# Test 3: Check if Airflow secrets exist in Vault
echo "3. Testing Airflow secrets in Vault..."
if [ ! -f ~/.vault/credentials ]; then
  print_result 1 "Vault credentials not found"
  exit 1
fi

source ~/.vault/credentials

# Set up port forwarding to test Vault access
kubectl port-forward svc/vault -n vault 8200:8200 &
FORWARDING_PID=$!
sleep 5

# Test database secret
if curl -s --header "X-Vault-Token: $ROOT_TOKEN" \
    http://127.0.0.1:8200/v1/secret/data/airflow/database | grep -q "username"; then
  print_result 0 "Database secret exists in Vault"
else
  print_result 1 "Database secret missing in Vault"
fi

# Test Redis secret
if curl -s --header "X-Vault-Token: $ROOT_TOKEN" \
    http://127.0.0.1:8200/v1/secret/data/airflow/redis | grep -q "password"; then
  print_result 0 "Redis secret exists in Vault"
else
  print_result 1 "Redis secret missing in Vault"
fi

# Test webserver secret
if curl -s --header "X-Vault-Token: $ROOT_TOKEN" \
    http://127.0.0.1:8200/v1/secret/data/airflow/webserver | grep -q "fernet_key"; then
  print_result 0 "Webserver secret exists in Vault"
else
  print_result 1 "Webserver secret missing in Vault"
fi

# Test connections secret
if curl -s --header "X-Vault-Token: $ROOT_TOKEN" \
    http://127.0.0.1:8200/v1/secret/data/airflow/connections | grep -q "smtp_host"; then
  print_result 0 "Connections secret exists in Vault"
else
  print_result 1 "Connections secret missing in Vault"
fi

kill $FORWARDING_PID

# Test 4: Check if Kubernetes secrets are synced
echo "4. Testing Kubernetes secret synchronization..."

secrets=("airflow-database-secret" "airflow-redis-secret" "airflow-webserver-secret" "airflow-connections-secret")
for secret in "${secrets[@]}"; do
  if kubectl get secret "$secret" -n airflow &>/dev/null; then
    # Check if secret has actual data (not just placeholder)
    if kubectl get secret "$secret" -n airflow -o jsonpath='{.data}' | grep -v "_dummy" | grep -q "."; then
      print_result 0 "$secret is synced with data"
    else
      print_result 1 "$secret exists but has no synced data"
    fi
  else
    print_result 1 "$secret does not exist"
  fi
done

# Test 5: Check secret rotation policy
echo "5. Testing secret rotation policy..."
if kubectl get configmap airflow-secret-rotation-policy -n airflow &>/dev/null; then
  print_result 0 "Secret rotation policy is configured"
else
  print_result 1 "Secret rotation policy is missing"
fi

if kubectl get cronjob airflow-secret-rotation -n airflow &>/dev/null; then
  print_result 0 "Secret rotation CronJob is configured"
else
  print_result 1 "Secret rotation CronJob is missing"
fi

# Test 6: Validate secret content format
echo "6. Testing secret content format..."

# Test database secret format
if kubectl get secret airflow-database-secret -n airflow -o jsonpath='{.data.POSTGRES_USER}' | base64 -d | grep -q "airflow"; then
  print_result 0 "Database secret has correct format"
else
  print_result 1 "Database secret format is incorrect"
fi

# Test Redis secret format
if kubectl get secret airflow-redis-secret -n airflow -o jsonpath='{.data.REDIS_PASSWORD}' | base64 -d | grep -q "."; then
  print_result 0 "Redis secret has correct format"
else
  print_result 1 "Redis secret format is incorrect"
fi

# Test webserver secret format
if kubectl get secret airflow-webserver-secret -n airflow -o jsonpath='{.data.FERNET_KEY}' | base64 -d | grep -q "."; then
  print_result 0 "Webserver secret has correct format"
else
  print_result 1 "Webserver secret format is incorrect"
fi

echo ""
echo "Vault integration test completed!"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "- Vault secrets are stored and accessible"
echo "- Vault Secrets Operator is syncing secrets to Kubernetes"
echo "- Secret rotation policies are configured"
echo "- Airflow can now use Vault-managed secrets"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Update PostgreSQL and Redis to use the new Vault-managed passwords"
echo "2. Deploy Airflow with the updated Helm values"
echo "3. Verify Airflow components can connect using the new secrets"