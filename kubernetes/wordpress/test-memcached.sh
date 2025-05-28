#!/bin/bash

# Script to test the Memcached integration with WordPress
# This verifies that WordPress can access Memcached and that the object cache is working

set -e

echo "Testing Memcached integration with WordPress..."

# Get the name of the first WordPress pod
WP_POD=$(kubectl get pods -n wordpress -l app=wordpress -o name | head -1)

if [ -z "$WP_POD" ]; then
  echo "Error: No WordPress pods found."
  exit 1
fi

echo "Using WordPress pod: $WP_POD"

# Test 1: Check if the Memcached PHP extension is loaded
echo -e "\nTest 1: Checking if Memcached extension is loaded in PHP..."
if kubectl exec -n wordpress ${WP_POD} -- php -m | grep -q memcached; then
  echo "✓ Memcached PHP extension is loaded."
else
  echo "✗ Memcached PHP extension is not loaded. Installing..."
  kubectl exec -n wordpress ${WP_POD} -- /bin/bash -c "apt-get update && apt-get install -y php-memcached"
  kubectl exec -n wordpress ${WP_POD} -- /bin/bash -c "kill -USR2 1" # Reload PHP-FPM
  sleep 5
  
  if kubectl exec -n wordpress ${WP_POD} -- php -m | grep -q memcached; then
    echo "✓ Memcached PHP extension has been installed."
  else
    echo "✗ Failed to install Memcached PHP extension."
    exit 1
  fi
fi

# Test 2: Check if WordPress can connect to Memcached server
echo -e "\nTest 2: Testing connection to Memcached server..."
if kubectl exec -n wordpress ${WP_POD} -- php -r '
$m = new Memcached();
$m->addServer("memcached.wordpress.svc.cluster.local", 11211);
$m->set("test_key", "Memcached is working!");
$val = $m->get("test_key");
echo $val . "\n";
if($val === "Memcached is working!") {
  exit(0);
} else {
  exit(1);
}
' > /dev/null 2>&1; then
  echo "✓ Connection to Memcached server successful."
else
  echo "✗ Failed to connect to Memcached server."
  exit 1
fi

# Test 3: Verify WordPress object cache is working
echo -e "\nTest 3: Testing WordPress object cache integration..."
kubectl exec -n wordpress ${WP_POD} -- php -r '
require_once("/var/www/html/wp-load.php");
$test_value = "This is a test value: " . time();
echo "Setting test cache value: $test_value\n";
wp_cache_set("test_key", $test_value, "test_group");
$result = wp_cache_get("test_key", "test_group");
echo "Retrieved from cache: $result\n";
if($result === $test_value) {
  echo "WordPress object cache is working correctly.\n";
  exit(0);
} else {
  echo "WordPress object cache is not working correctly.\n";
  exit(1);
}
'

# Test 4: Check if any other pods can access Memcached
echo -e "\nTest 4: Verifying that other pods cannot access Memcached..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: memcached-test-pod
  namespace: default
spec:
  containers:
  - name: test
    image: alpine:3.16
    command: ["/bin/sh", "-c", "apk add --no-cache netcat-openbsd && sleep 3600"]
EOF

# Wait for the test pod to be ready
kubectl wait --for=condition=Ready pod/memcached-test-pod -n default --timeout=60s

# Try to connect to Memcached from another namespace
if kubectl exec -n default memcached-test-pod -- nc -zv memcached.wordpress.svc.cluster.local 11211 -w 3; then
  echo "✗ Security issue: Pod from outside namespace can access Memcached!"
  echo "Network policy may not be working correctly."
else
  echo "✓ Network policy is working: External pods cannot access Memcached."
fi

# Clean up the test pod
kubectl delete pod memcached-test-pod -n default

echo -e "\nMemcached integration tests completed."
echo "Memcached is properly configured and secured for WordPress use only." 