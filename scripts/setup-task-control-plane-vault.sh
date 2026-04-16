#!/bin/bash
# Interactive setup for Task Control Plane Vault secrets
# Usage: ./setup-task-control-plane-vault.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Task Control Plane Vault Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check Vault CLI
if ! command -v vault &> /dev/null; then
    echo -e "${RED}Error: vault CLI is not installed${NC}"
    echo "Visit: https://www.vaultproject.io/downloads"
    exit 1
fi

# Check VAULT_ADDR
VAULT_ADDR="${VAULT_ADDR:-https://vault.myrobertson.net:8200}"
echo "Vault Address: $VAULT_ADDR"

# Check VAULT_TOKEN
if [ -z "$VAULT_TOKEN" ]; then
    echo -e "${YELLOW}Warning: VAULT_TOKEN not set in environment${NC}"
    read -sp "Enter Vault Token: " VAULT_TOKEN
    echo ""
fi

export VAULT_ADDR
export VAULT_TOKEN

# Test connection
echo "Testing Vault connection..."
if ! vault status > /dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to Vault${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Vault connection successful${NC}"
echo ""

# Choose environment
echo "Select environment:"
echo "1) Production (prod)"
echo "2) Staging"
read -p "Enter choice (1 or 2): " env_choice

case $env_choice in
    1)
        ENVIRONMENT="prod"
        VIKUNJA_URL="https://tasks.myrobertson.com"
        AUTHELIA_URL="https://auth.myrobertson.com"
        ;;
    2)
        ENVIRONMENT="staging"
        VIKUNJA_URL="https://tasks.staging.myrobertson.net"
        AUTHELIA_URL="https://auth.staging.myrobertson.net"
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}Selected: ${ENVIRONMENT}${NC}"
echo ""

# Vikunja Token
echo -e "${YELLOW}Step 1: Vikunja API Token${NC}"
echo "Get your token from: ${VIKUNJA_URL}/settings/api"
echo "Create a token named 'nudge-worker' or similar"
read -sp "Enter Vikunja API Token: " VIKUNJA_TOKEN
echo ""

if [ -z "$VIKUNJA_TOKEN" ]; then
    echo -e "${RED}Error: Vikunja token cannot be empty${NC}"
    exit 1
fi

# OpenAI Key
echo ""
echo -e "${YELLOW}Step 2: OpenAI API Key${NC}"
echo "Get your key from: https://platform.openai.com/api-keys"
read -sp "Enter OpenAI API Key (sk-...): " OPENAI_KEY
echo ""

if [ -z "$OPENAI_KEY" ]; then
    echo -e "${RED}Error: OpenAI key cannot be empty${NC}"
    exit 1
fi

# Telegram (optional)
echo ""
echo -e "${YELLOW}Step 3: Telegram Credentials (optional)${NC}"
read -p "Do you have a Telegram bot? (y/n): " has_tg

TG_BOT_TOKEN=""
TG_WEBHOOK_SECRET=""

if [ "$has_tg" = "y" ] || [ "$has_tg" = "Y" ]; then
    read -sp "Enter Telegram Bot Token: " TG_BOT_TOKEN
    echo ""
    read -sp "Enter Telegram Webhook Secret: " TG_WEBHOOK_SECRET
    echo ""
fi

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo "Summary of secrets to create:"
echo -e "${BLUE}========================================${NC}"
echo "Environment: $ENVIRONMENT"
echo "Vault Path: secret/task-control-plane/$ENVIRONMENT"
echo ""
echo "task-control-plane-vikunja:"
echo "  VIKUNJA_API_TOKEN: [set]"
echo ""
echo "task-control-plane-openai:"
echo "  OPENAI_API_KEY: [set]"
echo ""
echo "task-control-plane-app:"
echo "  TELEGRAM_BOT_TOKEN: ${TG_BOT_TOKEN:-(empty)}"
echo "  TELEGRAM_WEBHOOK_SECRET: ${TG_WEBHOOK_SECRET:-(empty)}"
echo ""

read -p "Continue? (y/n): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cancelled"
    exit 0
fi

# Create secrets
echo ""
echo "Creating Vault secrets..."

# Vikunja secret
echo -n "  task-control-plane-vikunja... "
vault kv put "secret/task-control-plane/$ENVIRONMENT/vikunja" \
    VIKUNJA_API_TOKEN="$VIKUNJA_TOKEN" \
    > /dev/null 2>&1
echo -e "${GREEN}✓${NC}"

# OpenAI secret
echo -n "  task-control-plane-openai... "
vault kv put "secret/task-control-plane/$ENVIRONMENT/openai" \
    OPENAI_API_KEY="$OPENAI_KEY" \
    > /dev/null 2>&1
echo -e "${GREEN}✓${NC}"

# App secret
echo -n "  task-control-plane-app... "
vault kv put "secret/task-control-plane/$ENVIRONMENT/app" \
    TELEGRAM_BOT_TOKEN="$TG_BOT_TOKEN" \
    TELEGRAM_WEBHOOK_SECRET="$TG_WEBHOOK_SECRET" \
    > /dev/null 2>&1
echo -e "${GREEN}✓${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Vault secrets created successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Wait 60 seconds for Vault Secrets Operator to sync secrets to Kubernetes"
echo ""
echo "2. Verify secrets synced:"
echo "   kubectl get secret task-control-plane-vikunja -n default"
echo ""
echo "3. Reconcile Flux to redeploy services:"
echo "   kubectl -n flux-system annotate kustomization apps \\"
echo "     reconcile.fluxcd.io/requestedAt=\"\$(date -u +%Y-%m-%dT%H:%M:%SZ)\" \\"
echo "     --overwrite"
echo ""
echo "4. Watch rollout:"
echo "   kubectl rollout status deploy/agent-service -n default"
echo "   kubectl rollout status deploy/nudge-worker -n default"
echo ""
