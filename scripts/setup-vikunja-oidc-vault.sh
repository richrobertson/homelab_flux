#!/bin/bash
# Setup Vikunja OIDC secrets in Vault
# Usage: ./setup-vikunja-oidc-vault.sh
# Requires: VAULT_ADDR and VAULT_TOKEN environment variables to be set

set -e

# Configuration
VAULT_ADDR="${VAULT_ADDR:-https://vault.myrobertson.net:8200}"
PROD_PATH="secret/task-control-plane/prod/vikunja-oidc"
STAGING_PATH="secret/task-control-plane/staging/vikunja-oidc"
CLIENT_SECRET='$2b$12$G4e2wFGmXCHkQowZZZKOrecbdJik.gd7L5ORyoRVOL7uMZue8SpBW'

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Vikunja OIDC Vault Setup ===${NC}"
echo "Vault Address: $VAULT_ADDR"
echo ""

# Check if vault command exists
if ! command -v vault &> /dev/null; then
    echo -e "${RED}Error: vault CLI is not installed${NC}"
    exit 1
fi

# Check if VAULT_TOKEN is set
if [ -z "$VAULT_TOKEN" ]; then
    echo -e "${RED}Error: VAULT_TOKEN environment variable is not set${NC}"
    echo "Please set VAULT_TOKEN to your Vault authentication token"
    exit 1
fi

# Test Vault connectivity
echo "Testing Vault connectivity..."
if ! vault status > /dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to Vault at $VAULT_ADDR${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Vault connection successful${NC}"
echo ""

# Create production secret
echo "Creating production secret at $PROD_PATH..."
vault kv put "$PROD_PATH" \
    client_id="vikunja_prod" \
    client_secret="$CLIENT_SECRET" \
    > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Production secret created successfully${NC}"
else
    echo -e "${RED}✗ Failed to create production secret${NC}"
    exit 1
fi

# Create staging secret
echo "Creating staging secret at $STAGING_PATH..."
vault kv put "$STAGING_PATH" \
    client_id="vikunja_staging" \
    client_secret="$CLIENT_SECRET" \
    > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Staging secret created successfully${NC}"
else
    echo -e "${RED}✗ Failed to create staging secret${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Vault secrets setup complete ===${NC}"
echo ""
echo "Next steps:"
echo "1. Reconcile Flux to apply the changes:"
echo "   kubectl -n flux-system annotate kustomization apps reconcile.fluxcd.io/requestedAt=\"\$(date -u +%Y-%m-%dT%H:%M:%SZ)\" --overwrite"
echo ""
echo "2. Wait for deployments to be ready:"
echo "   kubectl rollout status deploy/vikunja -n default"
echo ""
echo "3. Verify the secrets are synced:"
echo "   kubectl get secret vikunja-oidc-secret -n default"
echo ""
