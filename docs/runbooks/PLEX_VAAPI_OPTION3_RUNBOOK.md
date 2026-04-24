# Option 3: Custom Plex VAAPI Image Build Runbook

**Status**: Approved for Implementation  
**Date**: 2026-04-11  
**Objective**: Build and deploy a custom Plex image with Ubuntu 24.04-compatible VAAPI libraries to enable hardware transcoding  
**Effort**: High (requires Docker build, registry push, Kubernetes redeploy)  
**Risk**: Medium (testing required before production rollout)

---

## Executive Summary

After extensive investigation, Plex Media Server's VAAPI hardware transcoding failure was isolated to **ABI incompatibility between Plex's bundled Transcoder binary and the libva/libdrm libraries** on Ubuntu 24.04-based nodes.

**This runbook provides the complete procedure to:**
1. Build a custom Plex Docker image with system-compatible libraries
2. Push the image to the container registry
3. Deploy and validate hardware transcoding in staging
4. (Optional) Roll out to production

---

## Problem Context

### Symptoms
```
Plex Transcoder Error: Failed to initialise VAAPI connection: -1 (unknown libva error)
```

### Root Cause Analysis
- **Plex bundled libs** (`/usr/lib/plexmediaserver/lib/libva.so.2`, `libdrm.so.2`) have ABI incompatibilities
- **System drivers** (`/usr/lib/x86_64-linux-gnu/libva.so.2`, iHD driver) expect different symbol versions
- **ffmpeg** works (uses system libs exclusively)
- **vainfo** works (system VAAPI tools)
- **Plex Transcoder** fails (uses bundled libs)

### What Works Today
✅ GPU device plugin allocation (`gpu.intel.com/i915: "1"`)  
✅ Device ownership and permissions (uid/gid 568)  
✅ Non-root pod security policy (runAsNonRoot: true)  
✅ VAAPI infrastructure (drivers, device nodes)  
✅ Other media servers with VAAPI (ffmpeg, Jellyfin)

### What Doesn't Work
❌ Plex + VAAPI as-is (all tested versions + images)

---

## Solution Architecture

### Approach
Replace Plex's bundled VAAPI libraries with versions built from **Ubuntu 24.04 base** (matching Talos nodes).

### Build Strategy
1. Start with `lscr.io/linuxserver/plex:latest` (supports non-root UID 568)
2. Install Ubuntu 24.04 `libva`, `libdrm`, Intel media driver packages
3. Copy system libraries into Plex lib directory to replace bundled versions
4. Test with `vainfo` and transcoding probe
5. Push to registry as `oci.trueforge.org/homelab/plex-vaapi:tag`

---

## Implementation Steps

### Phase 1: Build Custom Image

#### 1a. Build Locally (Linux/macOS with Docker)

```bash
cd /path/to/homelab_flux/docker-builds/plex-vaapi

# Make build script executable
chmod +x build-plex-vaapi.sh test-plex-vaapi.sh

# Build image locally
./build-plex-vaapi.sh --tag v1.43.0.10492-ubuntu24.04
```

**Expected output:**
```
=== Building Custom Plex Image with Ubuntu 24.04 VAAPI Libraries ===
Target: oci.trueforge.org/homelab/plex-vaapi:v1.43.0.10492-ubuntu24.04
Using: docker

Building image...
[...build output...]
✓ Build complete: oci.trueforge.org/homelab/plex-vaapi:v1.43.0.10492-ubuntu24.04
```

**Build time**: ~5-10 minutes (depends on cache and internet)

#### 1b. Build via GitHub Actions (Recommended for CI/CD)

Push the built files and trigger workflow:

```bash
# Already committed; trigger manually via GitHub UI:
# Actions → Build Custom Plex VAAPI Image → Run workflow
# - Tag: v1.43.0.10492-ubuntu24.04
# - Push to registry: ✓ checked
```

Or trigger via API:
```bash
curl -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/richrobertson/homelab_flux/actions/workflows/build-plex-vaapi.yml/dispatches \
  -d '{"ref":"main","inputs":{"tag":"v1.43.0.10492-ubuntu24.04","push":"true"}}'
```

---

### Phase 2: Push to Registry

#### 2a. Push From Local Build

```bash
cd docker-builds/plex-vaapi
./build-plex-vaapi.sh --push --tag v1.43.0.10492-ubuntu24.04
```

**Prerequisites:**
- Docker logged into `oci.trueforge.org`:
  ```bash
  docker login oci.trueforge.org
  # Username: <registry-user>
  # Password: <registry-token>
  ```

#### 2b. Verify Image in Registry

```bash
# Check image exists
docker pull oci.trueforge.org/homelab/plex-vaapi:v1.43.0.10492-ubuntu24.04

# Inspect metadata
docker inspect oci.trueforge.org/homelab/plex-vaapi:v1.43.0.10492-ubuntu24.04 | jq .
```

---

### Phase 3: Deploy to Staging

#### 3a. Update Plex Helm Chart Values

Edit [apps/staging/plex/plex-values.yaml](../../apps/staging/plex/plex-values.yaml):

```yaml
image:
  repository: oci.trueforge.org/homelab/plex-vaapi
  tag: v1.43.0.10492-ubuntu24.04  # Change from default
  pullPolicy: IfNotPresent
```

#### 3b. Commit and Push Changes

```bash
cd /path/to/homelab_flux
git add apps/staging/plex/plex-values.yaml
git commit -m "chore(staging): upgrade plex to custom VAAPI image"
git push origin main
```

#### 3c. Trigger Flux Reconciliation

```bash
export KUBECONFIG="$HOME/.kube/config.stage"

# Force immediate reconciliation
kubectl -n flux-system annotate gitrepository flux-system \
  reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite
kubectl -n flux-system annotate kustomization apps \
  reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite

# Wait for rollout
kubectl -n default rollout status deployment/plex --timeout=600s
```

#### 3d. Verify Deployment

```bash
export KUBECONFIG="$HOME/.kube/config.stage"

# Check pod status
kubectl -n default get pods -l app.kubernetes.io/name=plex -o wide
kubectl -n default get deploy plex -o wide

# Verify image
POD=$(kubectl -n default get pods -l app.kubernetes.io/name=plex -o jsonpath='{.items[0].metadata.name}')
kubectl -n default get pod "$POD" -o jsonpath='{.spec.containers[0].image}'
echo
```

---

### Phase 4: Validate VAAPI Functionality

#### 4a. Quick Test via Kubernetes

```bash
export KUBECONFIG="$HOME/.kube/config.stage"
POD=$(kubectl -n default get pods -l app.kubernetes.io/name=plex -o jsonpath='{.items[0].metadata.name}')

# Test VAAPI connection
kubectl -n default exec "$POD" -- bash -c '
  echo "=== Testing VAAPI Initialization ==="
  "/usr/lib/plexmediaserver/Plex Transcoder" -v error \
    -f lavfi -i testsrc2=size=128x72:rate=1 -t 1 \
    -init_hw_device vaapi=va:/dev/dri/renderD128 \
    -vf format=nv12,hwupload \
    -c:v h264_vaapi \
    -f null - 2>&1 | head -30
'
```

**Expected success output:**
```
Input #0, lavfi, from testsrc2=size=128x72:rate=1:
  Duration: 00:00:01.00, start: 0.000000, bitrate: N/A
    Stream #0:0: Video: rgb24, rgb24(tv, bt709), 128x72, 1 fps, 1 tbr, 1 tbn
[h264_vaapi @ ...] Using input frames context (format nv12)
frame=    1 fps=0.8 q=-1Lbitrate=...
```

**Expected failure output (if still broken):**
```
Failed to initialise VAAPI connection: -1 (unknown libva error)
```

#### 4b. Comprehensive Test Script

```bash
cd /path/to/homelab_flux/docker-builds/plex-vaapi
chmod +x test-plex-vaapi.sh
./test-plex-vaapi.sh --k8s --image oci.trueforge.org/homelab/plex-vaapi:v1.43.0.10492-ubuntu24.04
```

This will:
1. Create ephemeral test pod in staging cluster
2. Run VAAPI initialization test
3. Capture output and cleanup
4. Display results

#### 4c. Request a Test Transcode (Manual)

1. Access Plex Web UI (staging)
2. Select a video file
3. Request transcoding with **H.264 or HEVC quality**
4. Monitor Plex logs for VAAPI messages:

```bash
kubectl -n default logs -f $POD --all-containers=true | grep -i vaapi
```

**Success indicator** in Plex logs:
```
Intel MediaSDK -> Encoding will be done by GPU
VAAPI-accelerated transcoding in progress...
```

---

## Validation Checklist

| Task | Command | Expected Result |
|------|---------|-----------------|
| **Image published** | `docker pull oci.trueforge.org/homelab/plex-vaapi:...` | Image downloads successfully |
| **Pod running** | `kubectl get pods -l app.kubernetes.io/name=plex` | Pod in `Running` phase |
| **GPU allocation** | `kubectl get pod $POD -o json \| jq '.spec.containers[0].resources.limits'` | `gpu.intel.com/i915: 1` present |
| **Device accessible** | `kubectl exec $POD -- ls -l /dev/dri/renderD128` | Permission success (no error) |
| **VAAPI init** | `kubectl exec $POD -- "Plex Transcoder" -init_hw_device vaapi=...` | No "Failed to initialise VAAPI" error |
| **Transcoding** | Manual video transcode in Plex UI | Video encodes without errors |
| **Plex stable** | `kubectl get deploy plex` | Replicas: 1/1 Ready |

---

## Rollback Procedure

If custom image causes issues:

```bash
# Revert to standard linuxserver/plex
cd /path/to/homelab_flux
git revert HEAD  # Or manually edit apps/staging/plex/plex-values.yaml
# Change back to: image: lscr.io/linuxserver/plex:latest

git commit -m "Rollback: custom Plex VAAPI image"
git push origin main

# Reconcile Flux
kubectl -n flux-system annotate kustomization apps \
  reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite
kubectl -n default rollout status deployment/plex --timeout=600s
```

Rollback time: **~5 minutes**

---

## Production Rollout (Optional)

Once validated in staging:

### 1. Promote to Production

```bash
# Update production values
vi apps/production/plex/plex-values.yaml
# Change to custom image tag

git add apps/production/plex/plex-values.yaml
git commit -m "feat(prod): deploy Plex with VAAPI hardware transcoding"
git push origin main
```

### 2. Monitor in Production

```bash
export KUBECONFIG="$HOME/.kube/config.prod"
kubectl -n default watch pods -l app.kubernetes.io/name=plex
kubectl -n default logs -f $(kubectl -n default get pods -l app.kubernetes.io/name=plex -o jsonpath='{.items[0].metadata.name}') --tail=50
```

### 3. Verify Transcoding

- Monitor media library for transcoding requests
- Check Plex UI for GPU utilization indicators
- Validate no CPU spikes (indicates software fallback)

---

## Troubleshooting Guide

### Image Build Fails

**Problem**: Build step fails with "package not found"

**Solution**:
```bash
# Check if Ubuntu 24.04 package exists
apt-cache search libva | grep -E "libva|libdrm"

# Update package names in Dockerfile if needed
# Rebuild: ./build-plex-vaapi.sh
```

### Image Size Too Large

**Problem**: Image exceeds registry limits

**Solution**:
- Multi-stage build (separate builder from runtime)
- Remove build tools in final layer
- See "Advanced: Multi-stage Build" section below

### VAAPI Still Fails After Deployment

**Problem**: Same "Failed to initialise VAAPI connection" error

**Analysis steps**:
```bash
POD=$(kubectl -n default get pods -l app.kubernetes.io/name=plex -o jsonpath='{.items[0].metadata.name}')

# Check library versions
kubectl exec $POD -- ldd /usr/lib/plexmediaserver/lib/libva.so.2

# Verify system driver loaded
kubectl exec $POD -- vainfo --display drm --device /dev/dri/renderD128

# Check ld.so cache
kubectl exec $POD -- ldconfig -p | grep libva

# Inspect Plex config for hardware accel setting
kubectl exec $POD -- grep -i "HardwareAccel" /config/Library/Application\ Support/Plex\ Media\ Server/Preferences.xml
```

**Possible causes**:
- Plex configuration has hardware acceleration disabled
- Bundled libc still conflicting (needs deeper replacement)
- Plex version too old/new for VAAPI support

---

## Advanced: Multi-stage Build (Optional Optimization)

To reduce image size, use multi-stage build:

```dockerfile
# docker-builds/plex-vaapi/Dockerfile.multistage
FROM lscr.io/linuxserver/plex:latest AS builder
# ... install dev packages, extract/replace libraries ...

FROM lscr.io/linuxserver/plex:latest AS runtime
COPY --from=builder /usr/lib/plexmediaserver /usr/lib/plexmediaserver
# ... minimal runtime setup ...
```

Build with:
```bash
docker build -f Dockerfile.multistage -t myimage .
```

---

## Maintenance & Versioning

### Update Custom Image When:
- ✅ New Plex version released (extract new tag, rebuild)
- ✅ Ubuntu 24.04 receives libva/libdrm updates (rebuild)
- ✅ Intel media driver has critical fixes (rebuild)

### Version Naming Scheme
```
oci.trueforge.org/homelab/plex-vaapi:<plex-version>-ubuntu24.04-<date>

Examples:
- v1.43.0.10492-ubuntu24.04-2026-04-11
- v1.44.0.12345-ubuntu24.04-latest
```

### Rebuild Command
```bash
cd docker-builds/plex-vaapi
./build-plex-vaapi.sh --push --tag v1.43.1-ubuntu24.04-$(date +%Y%m%d)
```

---

## References & Documentation

- **Previous Investigation**: See conversation summary for all VAAPI testing results
- **Dockerfile**: [docker-builds/plex-vaapi/Dockerfile](../../docker-builds/plex-vaapi/Dockerfile)
- **Build Script**: [docker-builds/plex-vaapi/build-plex-vaapi.sh](../../docker-builds/plex-vaapi/build-plex-vaapi.sh)
- **Test Script**: [docker-builds/plex-vaapi/test-plex-vaapi.sh](../../docker-builds/plex-vaapi/test-plex-vaapi.sh)
- **CI/CD Workflow**: [.github/workflows/build-plex-vaapi.yml](../../.github/workflows/build-plex-vaapi.yml)
- **Plex Transcoding Docs**: https://support.plex.tv/articles/200250387-transcoding/
- **VA-API Documentation**: https://github.com/intel/libva
- **Intel iHD Driver**: https://github.com/intel/media-driver

---

## Timeline

| Phase | Est. Duration | Status |
|-------|---------------|--------|
| **Build** (local or CI/CD) | 10-15 min | Ready |
| **Push to registry** | 2-5 min | Ready |
| **Deploy to staging** | 2-5 min | Ready |
| **Validate VAAPI** | 5-10 min | Ready |
| **Production rollout** | 2-5 min | Optional |
| **Total** | ~30-40 min | **Ready to execute** |

---

## Success Criteria

✅ **Option 3 is successful when:**
1. Custom image builds without errors
2. Image pushed to `oci.trueforge.org/homelab/plex-vaapi`
3. Plex pod deployed with new image in staging
4. VAAPI transcoding test completes without "Failed to initialise VAAPI connection" error
5. Manual video transcode in Plex UI succeeds with GPU utilization
6. Pod remains stable (no restarts, logs clean)

---

## Contact & Escalation

If build or deployment fails:
1. Check troubleshooting guide above
2. Review Dockerfile for Ubuntu 24.04 package availability
3. Escalate to image maintainers if linuxserver/plex base breaks
4. Consider alternative: Jellyfin (known to work with VAAPI)

---

**Document Version**: 1.0  
**Last Updated**: 2026-04-11  
**Author**: Custom image build automation
