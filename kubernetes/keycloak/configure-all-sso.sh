#!/bin/bash
set -e

# ANSI color codes
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo -e "${BLUE}====================================${NC}"
echo -e "${BLUE}   Keycloak SSO Complete Setup      ${NC}"
echo -e "${BLUE}====================================${NC}"
echo

# Check if Keycloak is running
echo -e "${BLUE}Checking if Keycloak is running...${NC}"
if ! kubectl get deployment -n keycloak keycloak &>/dev/null; then
    echo -e "${RED}Keycloak deployment not found. Exiting.${NC}"
    exit 1
fi
echo -e "${GREEN}Keycloak is running.${NC}"
echo

# Configure Grafana SSO
echo -e "${BLUE}====================================${NC}"
echo -e "${BLUE}   Configuring Grafana SSO          ${NC}"
echo -e "${BLUE}====================================${NC}"
./kubernetes/keycloak/configure-grafana-sso.sh
echo

# Configure n8n SSO
echo -e "${BLUE}====================================${NC}"
echo -e "${BLUE}   Configuring n8n SSO              ${NC}"
echo -e "${BLUE}====================================${NC}"
./kubernetes/keycloak/configure-n8n-sso.sh
echo

# Configure WordPress SSO
echo -e "${BLUE}====================================${NC}"
echo -e "${BLUE}   Configuring WordPress SSO        ${NC}"
echo -e "${BLUE}====================================${NC}"
./kubernetes/keycloak/configure-wordpress-sso.sh
echo

echo -e "${GREEN}====================================${NC}"
echo -e "${GREEN}   SSO Configuration Complete!      ${NC}"
echo -e "${GREEN}====================================${NC}"
echo
echo -e "${YELLOW}Important notes:${NC}"
echo -e "1. For WordPress, you need to install the 'OpenID Connect Generic' plugin."
echo -e "   - See the 'wordpress-sso-instructions' ConfigMap for details."
echo -e "2. You may need to wait a moment for all applications to restart before the changes take effect."
echo -e "3. Test user credentials: username: testuser, password: testpassword"
echo -e "4. Client details are stored in Vault under the following paths:"
echo -e "   - secret/grafana-sso"
echo -e "   - secret/n8n-sso"
echo -e "   - secret/wordpress-sso"
echo
echo -e "${BLUE}For more information, see the README.md file.${NC}" 