#!/bin/bash

set -e

echo "Updating Grafana deployment to use Vault for secrets..."

# Patch the Grafana deployment to use Vault annotations
kubectl patch deployment -n monitoring kube-prometheus-stack-grafana --patch '
{
  "spec": {
    "template": {
      "metadata": {
        "annotations": {
          "vault.hashicorp.com/agent-inject": "true",
          "vault.hashicorp.com/agent-inject-status": "update",
          "vault.hashicorp.com/role": "grafana",
          "vault.hashicorp.com/agent-inject-secret-admin-credentials": "secret/grafana/admin",
          "vault.hashicorp.com/agent-inject-template-admin-credentials": "{{- with secret \"secret/grafana/admin\" -}}
[security]\nadmin_user = {{ .Data.data.username }}\nadmin_password = {{ .Data.data.password }}\n{{- end -}}"
        }
      },
      "spec": {
        "serviceAccountName": "vault-auth",
        "containers": [
          {
            "name": "grafana",
            "env": [
              {
                "name": "GF_SECURITY_ADMIN_USER",
                "value": "${VAULT_AGENT_SECRETS_DIR}/admin-credentials"
              },
              {
                "name": "GF_SECURITY_ADMIN_PASSWORD",
                "value": "${VAULT_AGENT_SECRETS_DIR}/admin-credentials"
              }
            ]
          }
        ]
      }
    }
  }
}'

echo "Creating a sample secrets.yaml file without hardcoded credentials..."

cat > secure-grafana-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-secure-config
  namespace: monitoring
data:
  grafana.ini: |
    [security]
    # Credentials are now injected from Vault
    disable_initial_admin_creation = false
    
    [auth]
    disable_login_form = false
    disable_signout_menu = false
    oauth_auto_login = false
    
    [auth.basic]
    enabled = true
    
    [auth.proxy]
    enabled = false
    
    [auth.oauth]
    enabled = false
    
    [auth.ldap]
    enabled = false
    
    [users]
    allow_sign_up = false
    auto_assign_org = true
    auto_assign_org_role = Viewer
EOF

kubectl apply -f secure-grafana-config.yaml

echo "Updating helper scripts to remove hardcoded credentials..."

# Create a credentials-free script template for future use
cat > secure-grafana-helper.sh << EOF
#!/bin/bash

set -e

# No hardcoded credentials here!
# Credentials are retrieved from Vault

# Example function to get credentials from Vault
get_grafana_credentials() {
  # This is a placeholder function that should be implemented
  # based on your preferred method of accessing Vault
  # Options include:
  # 1. Using the Vault CLI
  # 2. Using the Vault API
  # 3. Using the Kubernetes-Vault integration
  
  # Example using Vault CLI (requires VAULT_ADDR and VAULT_TOKEN):
  # ADMIN_USER=\$(vault kv get -field=username secret/grafana/admin)
  # ADMIN_PASSWORD=\$(vault kv get -field=password secret/grafana/admin)
  
  echo "This is a template for secure credential handling."
}

# Call the function when needed
# get_grafana_credentials
EOF

echo "Grafana deployment has been updated to use Vault for secrets."
echo ""
echo "Next steps:"
echo "1. Make sure Vault is properly configured in your cluster"
echo "2. Test the integration by checking if Grafana can start correctly"
echo "3. Update all scripts to use the secure pattern shown in secure-grafana-helper.sh"
echo "4. Delete all files containing hardcoded credentials once the Vault integration is working" 