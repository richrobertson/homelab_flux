# Task Control Plane Deployment - Final Steps

## Current Status

- ✅ Vikunja OIDC integration configured
- ✅ Authelia OIDC clients created  
- ✅ agent-service Dockerfile fixed (PYTHONPATH added)
- ✅ All Kubernetes manifests in place
- ⏳ GitHub Actions rebuilding agent-service image (in progress)
- ⏳ Vault secrets need to be populated by user
- ⏳ Deployments waiting for credentials + rebuilt image

## Step-by-Step Completion Guide

### Step 1: Populate Vault Secrets (5-10 minutes)

The deployments are failing because they need real API credentials. Use the interactive setup script:

```bash
cd /Users/rich/Documents/GitHub/homelab_flux

# Set your Vault token
export VAULT_ADDR="https://vault.myrobertson.net:8200"
export VAULT_TOKEN="<your-vault-token>"

# Run the interactive script
./scripts/setup-task-control-plane-vault.sh
```

**You will need:**
1. **Vikunja API Token** - Get from https://tasks.myrobertson.com/settings/api
   - Click "Create API Token"
   - Name it "nudge-worker" or similar
   - Copy the token string
   
2. **OpenAI API Key** - Get from https://platform.openai.com/api-keys
   - Create a new secret key
   - Copy the sk-... token
   
3. **Telegram Credentials** (optional) - Leave blank if you don't have a bot

### Step 2: Verify Secrets Synced to Kubernetes (2 minutes)

After the script completes, wait for the Vault Secrets Operator to sync the secrets:

```bash
# Wait for sync (operator checks every 60 seconds)
sleep 60

# Verify secrets are in Kubernetes
kubectl get secret task-control-plane-vikunja -n default -o yaml | grep VIKUNJA_API_TOKEN

# Check if value is synced (not placeholder)
kubectl get secret task-control-plane-vikunja -n default -o jsonpath='{.data.VIKUNJA_API_TOKEN}' | base64 -d
```

### Step 3: Wait for Agent-Service Image Rebuild (5-15 minutes)

GitHub Actions is rebuilding the agent-service image with the PYTHONPATH fix. You can monitor progress:

```bash
# Check if image is available (will eventually succeed)
docker pull ghcr.io/richrobertson/agent-service:0.1.0

# Or check via git log
git log --oneline | head -5
```

### Step 4: Reconcile Flux to Deploy Services (2 minutes)

Once you've confirmed:
- ✅ Vault secrets are synced to Kubernetes
- ✅ GitHub Actions image rebuild is complete

Trigger Flux to redeploy:

```bash
kubectl -n flux-system annotate kustomization apps \
  reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --overwrite
```

Flux will:
1. Fetch the latest git commit (ecf87e2)
2. Parse the Kustomization
3. Pull the updated agent-service image
4. Deploy both agent-service and nudge-worker with real credentials

### Step 5: Monitor Deployment Rollout (3-5 minutes)

Watch the deployments come up:

```bash
# Watch agent-service rollout
kubectl rollout status deploy/agent-service -n default --timeout=5m

# Watch nudge-worker rollout  
kubectl rollout status deploy/nudge-worker -n default --timeout=5m
```

Check pod status:

```bash
kubectl get pods -n default -l app.kubernetes.io/part-of=task-control-plane
```

### Step 6: Verify Services Are Healthy (1 minute)

Once pods are running:

```bash
# Check agent-service health
kubectl exec -it deploy/agent-service -n default -- curl -s http://localhost:8080/healthz | jq .

# Check nudge-worker is polling
kubectl logs deploy/nudge-worker -n default --tail=50

# Check agent-service is starting up
kubectl logs deploy/agent-service -n default --tail=50
```

### Step 7: Test Vikunja OIDC Login (2-3 minutes)

Once everything is running, test the OIDC flow:

1. Navigate to https://tasks.myrobertson.com
2. Click "Login" or the OIDC provider button
3. Authenticate with LDAP credentials (ldap@myrobertson.net format)
4. Verify redirect back to Vikunja and you're logged in

Check that user was created in Vikunja:

```bash
# Get Vikunja pod
VIKUNJA_POD=$(kubectl get pod -n default -l app.kubernetes.io/name=vikunja -o name | head -1)

# Query the database
kubectl exec -it $VIKUNJA_POD -n default -- psql -U vkunja -d vikunja -c "SELECT id, email, username FROM users LIMIT 5;"
```

## Troubleshooting

### If Deployments Still Fail After Flux Reconciliation

Check pod logs:

```bash
# Agent-service error logs
kubectl logs deploy/agent-service -n default --tail=100 | grep -i error

# Nudge-worker error logs
kubectl logs deploy/nudge-worker -n default --tail=100 | grep -i error
```

**Common Issues:**

| Error | Solution |
|-------|----------|
| `ModuleNotFoundError: No module named 'agent_service'` | Image rebuild not complete yet (GitHub Actions in progress) |
| `Illegal header value b'Bearer '` | Vault secrets not synced - check `kubectl get secret task-control-plane-vikunja` |
| `Connection refused` | Vikunja service not reachable - check Vikunja pod is running |
| `invalid credentials` | Wrong Vikunja API token - re-run setup script |

### Check Vault Secret Sync Status

```bash
# List all VaultStaticSecrets
kubectl get secrets.hashicorp.com -n default

# Check sync for specific secret
kubectl describe secrets.hashicorp.com task-control-plane-vikunja -n default
```

### Verify GitHub Actions Image Build

Check if the Dockerfile change triggered the build:

```bash
# Push the Dockerfile fix (should trigger workflow)
git push

# Monitor workflow status (requires gh CLI or GitHub web interface)
gh run list --workflow=build-agent-service.yml -L 5
```

## Quick Reference

| Component | Status | Next Action |
|-----------|--------|-------------|
| OIDC Config | ✅ Ready | Waiting for credentials |
| Agent-Service Dockerfile | ✅ Fixed | Image rebuilding in Actions |
| Vault Setup Script | ✅ Ready | **Run this now** |
| Kubernetes Manifests | ✅ Ready | Will deploy on Flux reconcile |

## Timeline

```
Now ────────────────────────────────────────────────────────────→ Complete
     │                    │                    │                  │
     └─ Run Setup      ───└─ Wait 60s       ───└─ Reconcile   ───└─ Healthy
        Script (5m)         for Sync (60s)      Flux (2m)         Deployment
                                                                   (5m)
        
        Total Time: ~13-17 minutes
```

## Environment Variables Used

The deployments will use these environment variables from the Vault secrets:

| Variable | Source Secret | Used By |
|----------|---------------|---------|
| `VIKUNJA_API_TOKEN` | task-control-plane-vikunja | agent-service, nudge-worker |
| `OPENAI_API_KEY` | task-control-plane-openai | agent-service, nudge-worker |
| `TELEGRAM_BOT_TOKEN` | task-control-plane-app | agent-service (optional) |
| `TELEGRAM_WEBHOOK_SECRET` | task-control-plane-app | agent-service (optional) |

All other settings (URLs, model names, timeouts) are in ConfigMaps and don't require secrets.

## Success Criteria

✅ You'll know it's working when you see:

1. Pods are Running and Ready:
   ```
   NAME                    READY   STATUS    
   agent-service-xxx       1/1     Running   
   nudge-worker-xxx        1/1     Running   
   ```

2. Services are responding:
   ```
   $ kubectl exec deploy/agent-service -- curl -s http://localhost:8080/healthz
   {"status":"ok","service":"agent-service","now":"2026-04-16T..."}
   ```

3. Nudge-worker is polling:
   ```
   $ kubectl logs deploy/nudge-worker --tail=5
   2026-04-16T... nudge_scan_complete: scanned 5 tasks, found 1 due_soon, 0 overdue, 0 inactive
   ```

4. Vikunja OIDC login works:
   - Navigate to https://tasks.myrobertson.com
   - Click login
   - OIDC provider option appears
   - Login with LDAP credentials succeeds
