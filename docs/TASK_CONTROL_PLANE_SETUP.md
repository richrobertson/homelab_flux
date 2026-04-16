# Task Control Plane - Required Vault Secrets Setup

The nudge-worker and agent-service deployments are failing because the required Vault secrets have not been configured with actual credentials. This document provides instructions for setting up each required secret.

## Required Secrets Summary

| Vault Path | Description | Required Keys |
|---|---|---|
| `secret/task-control-plane/prod/vikunja` | Vikunja API credentials | `VIKUNJA_API_TOKEN` |
| `secret/task-control-plane/prod/openai` | OpenAI API key | `OPENAI_API_KEY` |
| `secret/task-control-plane/prod/app` | App-specific tokens | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_WEBHOOK_SECRET` |
| `secret/task-control-plane/prod/vikunja-oidc` | Vikunja OIDC credentials | `client_id`, `client_secret` |

(Replace `prod` with `staging` for staging environment)

## 1. Vikunja API Token

### What It Is
A personal access token used by nudge-worker and agent-service to query and update tasks in Vikunja.

### How to Generate
1. Log into Vikunja: https://tasks.myrobertson.com
2. Navigate to Settings → API Tokens
3. Create a new token with a descriptive name (e.g., "nudge-worker")
4. Copy the token value (long alphanumeric string)

### How to Store in Vault

```bash
export VAULT_ADDR="https://vault.myrobertson.net:8200"
export VAULT_TOKEN="<your-vault-token>"

# Production
vault kv put secret/task-control-plane/prod/vikunja \
  VIKUNJA_API_TOKEN="<token-from-vikunja-settings>"

# Staging (use staging Vikunja instance)
vault kv put secret/task-control-plane/staging/vikunja \
  VIKUNJA_API_TOKEN="<staging-token>"
```

## 2. OpenAI API Key

### What It Is
API key for the OpenAI service used by agent-service for chat interactions and nudge-worker for coaching message rewriting.

### How to Get
1. Create an account at https://platform.openai.com
2. Navigate to API keys section
3. Create a new secret key
4. Copy the key (starts with `sk-`)

### How to Store in Vault

```bash
# Production
vault kv put secret/task-control-plane/prod/openai \
  OPENAI_API_KEY="sk-..."

# Staging
vault kv put secret/task-control-plane/staging/openai \
  OPENAI_API_KEY="sk-..."
```

## 3. Telegram Credentials (Optional)

### What They Are
Optional webhook credentials for Telegram bot integration (agent-service can receive updates via Telegram).

### How to Store in Vault

```bash
# Production (if you have a Telegram bot)
vault kv put secret/task-control-plane/prod/app \
  TELEGRAM_BOT_TOKEN="<bot-token>" \
  TELEGRAM_WEBHOOK_SECRET="<secret>"

# Staging
vault kv put secret/task-control-plane/staging/app \
  TELEGRAM_BOT_TOKEN="<bot-token>" \
  TELEGRAM_WEBHOOK_SECRET="<secret>"
```

If you don't have a Telegram bot, use empty values:

```bash
vault kv put secret/task-control-plane/prod/app \
  TELEGRAM_BOT_TOKEN="" \
  TELEGRAM_WEBHOOK_SECRET=""
```

## 4. Vikunja OIDC Credentials

**Note: These are already set up via the setup script.** If you haven't run it yet:

```bash
export VAULT_ADDR="https://vault.myrobertson.net:8200"
export VAULT_TOKEN="<your-vault-token>"

./scripts/setup-vikunja-oidc-vault.sh
```

## Verification

After updating all secrets, verify the Kubernetes secrets are synced:

```bash
# Check secrets exist
kubectl get secret -n default | grep task-control-plane

# Verify secret contents
kubectl get secret task-control-plane-vikunja -n default -o yaml
kubectl get secret task-control-plane-openai -n default -o yaml
kubectl get secret task-control-plane-app -n default -o yaml

# Watch for sync (labels show when updated)
kubectl get secret task-control-plane-vikunja -n default -o jsonpath='{.metadata.labels}'
```

## Reconcile Flux

After all secrets are in Vault:

```bash
# Reconcile to redeploy with new secrets
kubectl -n flux-system annotate kustomization apps \
  reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --overwrite

# Watch deployment status
kubectl rollout status deploy/agent-service -n default
kubectl rollout status deploy/nudge-worker -n default
```

## Troubleshooting Deployment Failures

### Agent-service not starting

```bash
# Check pod logs
kubectl logs -n default deploy/agent-service --tail=50

# Common errors:
# - ModuleNotFoundError: agent_service module not found (PYTHONPATH issue)
# - Empty OPENAI_API_KEY or VIKUNJA_API_TOKEN
```

### Nudge-worker repeatedly crashing

```bash
# Check pod logs
kubectl logs -n default deploy/nudge-worker --tail=100

# Look for:
# - "Illegal header value b'Bearer '" → VIKUNJA_API_TOKEN is empty
# - Connection refused → VIKUNJA_BASE_URL or network issues
# - "Invalid credentials" → VIKUNJA_API_TOKEN is wrong
```

### Vault secret not syncing to Kubernetes

```bash
# Check VaultStaticSecret status
kubectl describe secrets.hashicorp.com task-control-plane-vikunja -n default
# or
kubectl get secrets.hashicorp.com -n default -o wide

# Check Vault Secrets Operator logs
kubectl logs -n vault-secrets-operator-system \
  -l app.kubernetes.io/name=vault-secrets-operator \
  --tail=50
```

### Pods stuck in CrashLoopBackOff

```bash
# Wait for all secrets to sync (check age)
kubectl get secret -n default task-control-* -o wide

# Then trigger a redeployment
kubectl rollout restart deploy/agent-service -n default
kubectl rollout restart deploy/nudge-worker -n default
```

## Quick Setup Script

If you have all the values ready, create a script like:

```bash
#!/bin/bash
set -e

export VAULT_ADDR="https://vault.myrobertson.net:8200"
export VAULT_TOKEN="${VAULT_TOKEN:-}"

if [ -z "$VAULT_TOKEN" ]; then
  echo "VAULT_TOKEN not set"
  exit 1
fi

# Vikunja token from https://tasks.myrobertson.com/settings/api
VIKUNJA_TOKEN=""

# OpenAI key from https://platform.openai.com/api-keys
OPENAI_KEY=""

# Telegram (optional)
TG_BOT_TOKEN=""
TG_WEBHOOK_SECRET=""

# Create production secrets
vault kv put secret/task-control-plane/prod/vikunja \
  VIKUNJA_API_TOKEN="$VIKUNJA_TOKEN"

vault kv put secret/task-control-plane/prod/openai \
  OPENAI_API_KEY="$OPENAI_KEY"

vault kv put secret/task-control-plane/prod/app \
  TELEGRAM_BOT_TOKEN="$TG_BOT_TOKEN" \
  TELEGRAM_WEBHOOK_SECRET="$TG_WEBHOOK_SECRET"

echo "✓ Production secrets configured"
```

## Security Notes

1. **Never commit secrets to git** - Always store in Vault
2. **Rotate tokens regularly** - Update Vault and redeploy pods
3. **Use least privileges** - OpenAI API keys and Vikunja tokens should have minimal required permissions
4. **Secure Vault access** - Protect VAULT_TOKEN with same care as passwords
