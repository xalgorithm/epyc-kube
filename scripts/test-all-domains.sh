#!/bin/bash

# Test all domains for connectivity
# This script tests both HTTP redirect and HTTPS response

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🌐 Testing DNS and connectivity for all domains${NC}"
echo "=================================================="

# List of all domains
DOMAINS=(
    "grafana.gray-beard.com"
    "automate.gray-beard.com"
    "automate2.gray-beard.com"
    "ethos.gray-beard.com"
    "ethosenv.gray-beard.com"
    "kampfzwerg.gray-beard.com"
    "login.gray-beard.com"
    "notify.gray-beard.com"
    "blackrock.gray-beard.com"
    "couchdb.blackrock.gray-beard.com"
    "vault.gray-beard.com"
)

test_domain() {
    local domain=$1
    echo -e "\n${BLUE}Testing: $domain${NC}"
    echo "------------------------"
    
    # Test DNS resolution
    echo -n "DNS Resolution: "
    if nslookup $domain >/dev/null 2>&1; then
        local ip=$(nslookup $domain | grep -A1 "Name:" | tail -1 | awk '{print $2}' 2>/dev/null || dig +short $domain | head -1)
        echo -e "${GREEN}✅ Resolves to: $ip${NC}"
    else
        echo -e "${RED}❌ DNS resolution failed${NC}"
        return 1
    fi
    
    # Test HTTP redirect
    echo -n "HTTP Redirect: "
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$domain" 2>/dev/null)
    if [ "$http_status" = "301" ] || [ "$http_status" = "302" ]; then
        echo -e "${GREEN}✅ HTTP redirects to HTTPS ($http_status)${NC}"
    else
        echo -e "${YELLOW}⚠️  HTTP status: $http_status${NC}"
    fi
    
    # Test HTTPS response
    echo -n "HTTPS Response: "
    local https_status=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 10 "https://$domain" 2>/dev/null)
    if [ "$https_status" = "200" ]; then
        echo -e "${GREEN}✅ HTTPS working (200)${NC}"
    elif [ "$https_status" = "302" ] || [ "$https_status" = "307" ]; then
        echo -e "${GREEN}✅ HTTPS working with redirect ($https_status)${NC}"
    elif [ "$https_status" = "404" ]; then
        echo -e "${YELLOW}⚠️  Service not found (404) - backend may be down${NC}"
    elif [ "$https_status" = "503" ]; then
        echo -e "${YELLOW}⚠️  Service unavailable (503) - backend may be starting${NC}"
    elif [ -z "$https_status" ] || [ "$https_status" = "000" ]; then
        echo -e "${RED}❌ Connection timeout or failed${NC}"
    else
        echo -e "${YELLOW}⚠️  HTTPS status: $https_status${NC}"
    fi
    
    # Test SSL certificate
    echo -n "SSL Certificate: "
    if echo | timeout 5 openssl s_client -connect $domain:443 -servername $domain >/dev/null 2>&1; then
        echo -e "${GREEN}✅ SSL handshake successful${NC}"
    else
        echo -e "${YELLOW}⚠️  SSL handshake failed (self-signed cert expected)${NC}"
    fi
}

# Test all domains
for domain in "${DOMAINS[@]}"; do
    test_domain "$domain"
done

echo -e "\n${BLUE}📊 Summary${NC}"
echo "=========="
echo -e "${GREEN}✅ Working domains should show:${NC}"
echo "   - DNS Resolution: ✅"
echo "   - HTTP Redirect: ✅ (301/302)"
echo "   - HTTPS Response: ✅ (200/302/307)"
echo "   - SSL Certificate: ✅ or ⚠️ (self-signed)"
echo ""
echo -e "${YELLOW}⚠️  Note: Self-signed SSL certificates are expected${NC}"
echo -e "${BLUE}💡 To get real SSL certificates, run: ./setup-letsencrypt.sh${NC}"