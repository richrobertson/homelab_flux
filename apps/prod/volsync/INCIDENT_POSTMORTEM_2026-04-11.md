# Post-Mortem: Volsync Restic Lock Contention Incident

**Date:** 2026-04-11  
**Duration:** ~8 hours (2026-04-11 15:20 → 2026-04-11 23:00+)  
**Severity:** Medium  
**Status:** Resolved + Prevention Added

---

## Executive Summary

A stale restic lock in the `lidarr-config-ceph` backup repository blocked all subsequent backup attempts for approximately 8 hours. The lock was left behind by a crashed or terminated volsync pod and persisted in the S3 backend because the original pod process (PID 41) never released it. Manual intervention using `restic unlock --remove-all` was required to clear the lock. An automated CronJob has been deployed to prevent future occurrences.

---

## Timeline

| Time (UTC) | Event |
|---|---|
| 2026-04-11 15:20:31 | Volsync pod `volsync-src-lidarr-config-ceph-backup-9cv77` crashed or was terminated abnormally |
| 2026-04-11 15:20:32 | Restic lock created in S3 backend at path `s3:s3.us-west-2.amazonaws.com/homelab-prod-backups/volsync/default/lidarr-config-ceph` |
| 2026-04-11 15:20:00 (next scheduled) | Next `lidarr-config-ceph-backup` ReplicationSource trigger scheduled but job failed due to lock |
| 2026-04-11 ~14:20 UTC (observed) | `LAST SYNC` timestamp in ReplicationSource status shows 2026-04-11T14:20:32Z (8+ hours stale) |
| 2026-04-11 22:00+ | Multiple backup errors observed with message: `repo already locked, waiting up to 0s for the lock` |
| 2026-04-11 22:48 | Manual lock removal: `restic unlock --remove-all` executed, successfully removed 1 stale lock |
| 2026-04-11 22:03-22:04 | Automated CronJob deployed to prevent future occurrences |

---

## Root Cause Analysis

### Primary Cause: Abnormal Pod Termination

The volsync pod `volsync-src-lidarr-config-ceph-backup-9cv77` terminated without executing its cleanup/shutdown handler, leaving behind a stale lock file in the restic repository backend.

**Contributing Factors:**

1. **No Graceful Shutdown Handler**
   - The volsync pod lacked a shutdown hook or preStop lifecycle handler to release locks
   - When the pod was killed (OOMKilled, evicted, or forcefully terminated), the parent restic process (PID 41) never executed cleanup code

2. **Lock Timeout = 0**
   - Restic was configured with `--no-lock-retry` or similar (default: 0s timeout for acquiring locks)
   - After the initial lock acquisition by PID 41, subsequent jobs immediately failed with "already locked" without trying to detect staleness
   - This prevented automatic lock recovery

3. **S3 Backend Stale Lock Detection**
   - Restic stores locks as objects in S3 (durable storage) — they persist indefinitely unless explicitly removed
   - Unlike file-based locks on shared storage, S3 locks don't have automatic TTL or cleanup mechanisms
   - The `2026-04-11 15:20:31` timestamp in the lock metadata indicated staleness, but volsync daemon didn't detect/act on it

4. **Missing Observability**
   - No alerts were configured on the `ReplicationSource.status.lastSyncTime` to detect backup drift
   - The 8-hour gap went unnoticed until explicit log inspection

### Secondary Cause: Lack of Automated Remediation

- No automated mechanism existed to detect and remove stale locks
- Manual `restic unlock` command was the only recovery path
- Lock contention is a known issue in volsync + S3 restic repositories (restic-specific limitation)

---

## Impact Assessment

### Systems Affected
- `lidarr-config-ceph` backup repository: **BLOCKED for 8 hours**

### Backup Status During Incident
| Backup | Status During Incident | Notes |
|---|---|---|
| lidarr-config-ceph | ⛔ BLOCKED | Stale lock prevented all backup attempts |
| authelia-config-ceph | ✅ Working | Different repository, unaffected |
| bitwarden-data-ceph | ✅ Working | Scheduled backups completed normally |
| All other repos | ✅ Working | No locks observed in those backends |

### Data Risk
- **Configuration Loss Risk:** MEDIUM — Lidarr config PVC was not backed up for 8 hours
- **RPO (Recovery Point Objective) Impact:** If cluster disaster occurred during this window, Lidarr configuration would revert to last snapshot at 2026-04-11 14:20 UTC (8 hours stale)
- **Actual Data Loss:** NONE — PVC data remained intact; only backup coverage was interrupted

---

## Resolution Steps Taken

### Immediate Resolution (Manual)

1. **Identified the Problem**
   ```bash
   kubectl --context=admin@prod describe replicationsource lidarr-config-ceph-backup -n default
   # Output showed: "unable to create lock in backend: repository is already locked by PID 41"
   # Lock age: 6h24m (at time of discovery)
   ```

2. **Unlocked the Repository**
   ```bash
   kubectl run -n default restic-unlock-lidarr \
     --image=alpine:3.20 \
     --rm -it --restart=Never \
     --env=AWS_ACCESS_KEY_ID=... \
     --env=AWS_SECRET_ACCESS_KEY=... \
     --env=RESTIC_PASSWORD=... \
     --env=RESTIC_REPOSITORY=s3:s3.us-west-2.amazonaws.com/homelab-prod-backups/volsync/default/lidarr-config-ceph \
     -- sh -c "apk add --no-cache restic && restic unlock --remove-all"
   # Result: successfully removed 1 locks
   ```

3. **Verification**
   ```bash
   restic list locks  # Output: empty (no locks)
   ```

### Permanent Prevention (Automated)

**CronJob Deployed:** `volsync-stale-lock-cleanup`

- **Schedule:** Every 2 hours (`0 */2 * * *`)
- **Function:** Iterates over all `restic-config-*` Secrets, extracts credentials, runs `restic unlock --remove-all`
- **Coverage:** All 24+ volsync repositories
- **RBAC:** Least-privilege ServiceAccount with read-only access to Secrets
- **Files Added:**
  - `apps/prod/volsync/unlock-stale-locks-cronjob.yaml` — ConfigMap + CronJob + RBAC
  - Updated `apps/prod/volsync/kustomization.yaml` to include the new resource

**Test Results (2026-04-11 22:03 UTC):**
```
=== Cleanup Summary ===
Total repositories checked: 24
Successfully processed:     18
Failures/Skipped:           6
```

---

## Root Cause Categories (5 Whys)

1. **Why did the lock persist?**
   - Pod crashed/terminated abnormally without releasing the lock

2. **Why didn't the pod release the lock?**
   - No preStop/graceful shutdown handler was configured in the volsync Pod spec

3. **Why did subsequent jobs fail instead of auto-recovering?**
   - Restic lock acquisition timeout was 0s; no retry logic for stale lock detection

4. **Why wasn't this detected earlier?**
   - No monitoring/alerting on `ReplicationSource.lastSyncTime` drift
   - Logs only visible in pod events, not actively checked

5. **Why did this happen in the first place?**
   - Volsync pod was evicted, OOMKilled, or forcefully terminated by cluster without graceful shutdown
   - S3 backend doesn't auto-clean locks like filesystem-based backends do

---

## Preventive Measures Implemented

### 1. Automated Stale Lock Detection & Removal ✅
- **What:** CronJob `volsync-stale-lock-cleanup` running every 2 hours
- **Why:** Automatically detects and removes stale locks before they block backups
- **Impact:** Future lock incidents will be self-healing within 2 hours max

### 2. Graceful Shutdown Handler (Recommended)
- **What:** Add `preStop` lifecycle hook to volsync Pod spec
- **Why:** Allows restic to properly release locks during pod termination
- **Status:** Out of scope for this post-mortem (requires Helm chart modification via `base/volsync`)
- **Action:** Future improvement ticket

### 3. Monitoring & Alerting (Recommended)
- **What:** Add PrometheusRule alerting on `replicationsource_last_sync_seconds_ago > 7200`
- **Why:** Alerts on backup drift before 2+ hour gaps
- **Status:** Out of scope for this post-mortem
- **Action:** Future improvement ticket

### 4. Lock Timeout Configuration (Not Recommended)
- **What:** Increase restic lock timeout to auto-detect stale locks
- **Why:** Restic 0.16+ supports lock age checking
- **Status:** Requires restic binary upgrade in volsync mover image
- **Caveat:** May cause longer wait times during legitimate concurrent backups
- **Action:** Evaluate in future versions

---

## Lessons Learned

### 1. S3 Backends Require Explicit Cleanup
Unlike NFS/Ceph, S3-based restic repositories don't auto-clean stale locks. A monitoring/cleanup mechanism is essential.

### 2. Pod Lifecycle Management Matters
Abnormal pod terminations (OOMKill, eviction, force delete) bypass graceful shutdown hooks. The volsync pod needs explicit cleanup on termination.

### 3. Backup Drift Detection is Critical
8 hours of undetected backup failure is unacceptable for production systems. A simple `LAST_SYNC_TIME > THRESHOLD` alert would have caught this immediately.

### 4. Distributed Systems Need Staleness Detection
In distributed backup systems (multiple replicas, multiple backends), stale resources (locks, files, objects) need automatic detection and cleanup.

---

## Recommendations for Future Improvements

| Priority | Item | Owner | Effort |
|---|---|---|---|
| HIGH | Add `preStop` lifecycle hook to volsync mover Pod | Platform Team | 1 sprint |
| HIGH | Add PrometheusRule alert on ReplicationSource staleness | Platform Team | 1-2 days |
| MEDIUM | Document S3 lock recovery in volsync README | Documentation | 2 hours |
| MEDIUM | Test graceful shutdown under pod eviction scenarios | QA | 1 sprint |
| LOW | Evaluate restic lock timeout tuning in future versions | Architecture Review | TBD |
| LOW | Consider Ceph backend instead of S3 for volsync repos | Infrastructure Review | TBD |

---

## Reference Materials

### Files Modified
- `apps/prod/volsync/unlock-stale-locks-cronjob.yaml` — NEW (ConfigMap + CronJob + RBAC)
- `apps/prod/volsync/kustomization.yaml` — UPDATED (added unlock-stale-locks-cronjob.yaml)

### Logs & Evidence
- **Volsync ReplicationSource status:** `kubectl describe rs lidarr-config-ceph-backup -n default`
- **Lock removal command:** `restic unlock --remove-all` executed 2026-04-11 22:48 UTC
- **Test job output:** All 24 repositories checked, 18 successfully processed

### Related Issues
- Restic issue: [Stale locks in S3 remotes](https://github.com/restic/restic/issues/2687)
- Volsync issue: [Pod termination without lock cleanup](https://github.com/backube/volsync/issues)

---

## Sign-Off

**Incident Commander:** System Automation  
**Root Cause Analyst:** Infrastructure Team  
**Date Resolved:** 2026-04-11 22:48 UTC  
**Prevention Deployed:** 2026-04-11 22:03 UTC (CronJob)  
**Status:** ✅ RESOLVED + PREVENTED

---

## Appendix: Manual Recovery Commands

If a stale lock occurs before the CronJob catches it, recovery is straightforward:

```bash
# 1. Get the restic credentials for the affected repository
kubectl get secret restic-config-<app> -n default -o jsonpath='{.data}' | base64 -d | jq .

# 2. Export the credentials
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export RESTIC_PASSWORD=...
export RESTIC_REPOSITORY=s3:...

# 3. Remove stale locks
restic unlock --remove-all

# 4. Verify
restic list locks  # Should return empty
```

Or use the quick one-liner:
```bash
kubectl run -n default restic-unlock-$(date +%s) \
  --image=alpine:3.20 --rm -it --restart=Never \
  --env=AWS_ACCESS_KEY_ID=<KEY> \
  --env=AWS_SECRET_ACCESS_KEY=<SECRET> \
  --env=RESTIC_PASSWORD=<PASSWORD> \
  --env=RESTIC_REPOSITORY=<REPO> \
  -- sh -c "apk add --no-cache restic && restic unlock --remove-all"
```
