#!/bin/bash
# Non-interactive setup - define your credentials and run
# Usage: Edit this file with your values, then run: bash setup-task-control-plane-vault-manual.sh

set -e

# ============================================================
# EDIT THESE VALUES
# ============================================================

# Vault Configuration
export VAULT_ADDR="${VAULT_ADDR:-https://vault.myrobertson.net:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-}"  # Set via environment or edit here

# Target Environment
ENVIRONMENT="${ENVIRONMENT:-prod}"  # Change to "staging" if needed

# Credentials - GET THESE FROM:
# - VIKUNJA_API_TOKEN: https://tasks.myrobertson.com/settings/api
# - OPENAI_API_KEY: https://platform.openai.com/api-keys
# - TELEGRAM_*: Your Telegram bot (optional, leave empty if none)

VIKUNJA_API_TOKEN="${VIKUNJA_API_TOKEN:-}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_WEBHOOK_SECRET="${TELEGRAM_WEBHOOK_SECRET:-}"

# ============================================================
# VALIDATION
# ============================================================

if ! command -v vault &> /dev/null; then
    echo "Error: vault CLI not installed"
    exit 1
fi

if [ -z "$VAULT_TOKEN" ]; then
    echo "Error: VAULT_TOKEN not set"
    echo "Set via: export VAULT_TOKEN='<your-token>'"
    exit 1
fi

if [ -z "$VIKUNJA_API_TOKEN" ]; then
    echo "Error: VIKUNJA_API_TOKEN not configured"
    echo "Get from: https://tasks.myrobertson.com/settings/api"
    exit 1
fi

if [ -z "$OPENAI_API_KEY" ]; then
    echo "Error: OPENAI_API_KEY not configured"
    echo "Get from: https://platform.openai.com/api-keys"
    exit 1
fi

# ============================================================
# SETUP
# ============================================================

echo "Configuring Task Control Plane Vault secrets for: $ENVIRONMENT"
echo "Vault: $VAULT_ADDR"
echo ""

# Test Vault connection
if ! vault status > /dev/null 2>&1; then
    echo "Error: Cannot connect to Vault at $VAULT_ADDR"
    exit 1
fi

echo "Creating Vault secrets..."

# Vikunja
echo -n "  task-control-plane-vikunja... "
vault kv put "secret/task-control-plane/$ENVIRONMENT/vikunja" \
    VIKUNJA_API_TOKEN="$VIKUNJA_API_TOKEN" > /dev/null
echo "done"

# OpenAI
echo -n "  task-control-plane-openai... "
vault kv put "secret/task-control-plane/$ENVIRONMENT/openai" \
    OPENAI_API_KEY="$OPENAI_API_KEY" > /dev/null
echo "done"

# App
echo -n "  task-control-plane-app... "
vault kv put "secret/task-control-plane/$ENVIRONMENT/app" \
    TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" \
    TELEGRAM_WEBHOOK_SECRET="$TELEGRAM_WEBHOOK_SECRET" > /dev/null
echo "done"

echo ""
echo "✓ Vault secrets created for $ENVIRONMENT environment"
echo ""
echo "Next steps:"
echo "1. Wait 60 seconds for Vault Secrets Operator to sync"
echo "2. Verify: kubectl get secret task-control-plane-vikunja -n default"
echo "3. Reconcile: kubectl -n flux-system annotate kustomization apps reconcile.fluxcd.io/requestedAt=\"\$(date -u +%Y-%m-%dT%H:%M:%SZ)\" --overwrite"
