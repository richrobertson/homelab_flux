# Fix Summary - Vikunja OIDC + Task Control Plane Issues

## Issues Found & Fixed

### 1. ✅ Agent-Service Dockerfile Missing PYTHONPATH
**Status**: FIXED (commit 7b825c1)

**Issue**: Container was crashing with `ModuleNotFoundError: No module named 'agent_service'`

**Fix**: Added `ENV PYTHONPATH=/app/src` to agent-service Dockerfile (matching nudge-worker)

**Action**: GitHub Actions will rebuild the image automatically on the next poll

### 2. 🔴 Missing Vault Secrets
**Status**: REQUIRES USER ACTION

Both agent-service and nudge-worker are crashing because these Vault secrets are empty/placeholder-only:

- `secret/task-control-plane/prod/vikunja` → needs `VIKUNJA_API_TOKEN`
- `secret/task-control-plane/prod/openai` → needs `OPENAI_API_KEY`  
- `secret/task-control-plane/staging/*` → same as above

**Error**: `httpx.LocalProtocolError: Illegal header value b'Bearer '` (empty token)

**Fix**: See docs/TASK_CONTROL_PLANE_SETUP.md for complete instructions

## What's Working

✅ Vikunja OIDC configuration (commit a7153d1)
✅ Authelia OIDC clients configured  
✅ Container image build pipeline
✅ Kubernetes manifests structure

## What Needs Doing

### Immediate (Blocking Deployment)

1. **Generate Vikunja API Token**
   - Log into https://tasks.myrobertson.com
   - Settings → API Tokens → Create Token
   - Store in Vault:
   ```bash
   export VAULT_ADDR="https://vault.myrobertson.net:8200"
   export VAULT_TOKEN="<your-token>"
   vault kv put secret/task-control-plane/prod/vikunja \
     VIKUNJA_API_TOKEN="<token-from-vikunja>"
   ```

2. **Get OpenAI API Key**
   - Get from https://platform.openai.com/api-keys
   - Store in Vault:
   ```bash
   vault kv put secret/task-control-plane/prod/openai \
     OPENAI_API_KEY="sk-..."
   ```

3. **Reconcile Flux** (after secrets are in Vault)
   ```bash
   kubectl -n flux-system annotate kustomization apps \
     reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     --overwrite
   ```

4. **Watch Deployments**
   ```bash
   kubectl rollout status deploy/agent-service -n default
   kubectl rollout status deploy/nudge-worker -n default
   ```

### Optional (For Telegram Integration)

```bash
vault kv put secret/task-control-plane/prod/app \
  TELEGRAM_BOT_TOKEN="<bot-token-or-empty>" \
  TELEGRAM_WEBHOOK_SECRET="<secret-or-empty>"
```

## Files Modified

- `docker-builds/agent-service/Dockerfile` → Added PYTHONPATH
- `apps/prod/authelia/authelia-values.yaml` → Added vikunja_prod OIDC client
- `apps/staging/authelia/authelia-values.yaml` → Added vikunja_staging OIDC client
- `apps/base/task-control-plane/vikunja/release.yaml` → Added OIDC env vars
- `apps/base/task-control-plane/secret-stubs.yaml` → Added vikunja-oidc-secret
- `apps/prod/task-control-plane/kustomization.yaml` → Added vikunja-oidc patch
- `apps/staging/task-control-plane/kustomization.yaml` → Added vikunja patches
- `docs/VIKUNJA_OIDC_SETUP.md` → OIDC integration guide (NEW)
- `docs/TASK_CONTROL_PLANE_SETUP.md` → Vault secrets guide (NEW)
- `scripts/setup-vikunja-oidc-vault.sh` → OIDC setup script (NEW)

## Timeline

1. **✅ Done**: Vikunja OIDC & Authelia integration configured
2. **✅ Done**: Agent-service Dockerfile fix (image rebuild queued)
3. **🔄 In Progress**: Image rebuild (triggered by GitHub Actions)
4. **⏳ Pending**: User provides Vikunja API token + OpenAI key
5. **⏳ Pending**: Flux reconciliation (after Vault secrets populated)
6. **⏳ Pending**: Deployments become ready

## Health Check

```bash
# Check secret sync status
kubectl get secrets.hashicorp.com -n default

# Check deployment readiness
kubectl get deploy agent-service nudge-worker -n default

# Watch pod logs
kubectl logs -f deploy/agent-service -n default
kubectl logs -f deploy/nudge-worker -n default
```

## Full Setup Documentation

See:
- `docs/VIKUNJA_OIDC_SETUP.md` - OIDC authentication flow
- `docs/TASK_CONTROL_PLANE_SETUP.md` - Vault secrets setup
