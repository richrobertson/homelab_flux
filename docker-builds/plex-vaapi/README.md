# Custom Plex VAAPI Image Build

## Latest Investigation Recap

- Full experiment recap:
  - [EXPERIMENT_RECAP_2026-04-22.md](./EXPERIMENT_RECAP_2026-04-22.md)

## Problem Statement

Plex Media Server's bundled Transcoder binary fails to initialize VAAPI hardware transcoding in the staging Kubernetes cluster with the error:
```
Failed to initialise VAAPI connection: -1 (unknown libva error)
```

**Root Cause**: Plex bundles its own versions of `libc`, `libva`, and `libdrm` that have ABI incompatibilities with the Intel iHD VAAPI driver loaded from the system on Ubuntu 24.04-based nodes.

**Evidence**:
- `vainfo` (system VAAPI tools) works correctly in Plex containers
- `ffmpeg` with VAAPI works correctly with the same GPU device plugin allocation
- Plex Transcoder binary fails identically across all tested container images and versions
- Root cause isolated: Plex's bundled transcoder binary + bundled libs incompatibility

## Solution

Replace Plex's bundled VAAPI libraries (`libva.so.2`, `libva-drm.so.2`, `libdrm.so.2`) with versions built from the same Ubuntu 24.04 base that matches the Talos nodes.

This ensures:
- ABI compatibility between Plex Transcoder and system drivers
- Hardware transcoding capability without pod security policy violations
- Non-root execution (UID 568) via linuxserver/plex base image

## Build Instructions

### Prerequisites

- Docker or Podman installed
- Access to container registry (`oci.trueforge.org/homelab/plex-vaapi`)
- ~2GB disk space for build

### Build Locally

```bash
cd docker-builds/plex-vaapi
chmod +x build-plex-vaapi.sh
./build-plex-vaapi.sh --tag v1.43.0.10492-ubuntu24.04
```

### Build and Push to Registry

```bash
./build-plex-vaapi.sh --push --tag v1.43.0.10492-ubuntu24.04
```

### Manual Build (Docker)

```bash
cd docker-builds/plex-vaapi
docker build -t oci.trueforge.org/homelab/plex-vaapi:v1.43.0.10492-ubuntu24.04 .
docker push oci.trueforge.org/homelab/plex-vaapi:v1.43.0.10492-ubuntu24.04
```

## Testing the Custom Image

### Local Validation

```bash
docker run --rm -it oci.trueforge.org/homelab/plex-vaapi:latest bash

# Inside container:
vainfo --display drm --device /dev/dri/renderD128  # Should show VA-API + iHD
"/usr/lib/plexmediaserver/Plex Transcoder" -hwaccels  # Should list vaapi
```

### Kubernetes Deployment

Update [plex-values.yaml](../../apps/staging/plex/plex-values.yaml):

```yaml
image:
  repository: oci.trueforge.org/homelab/plex-vaapi
  tag: v1.43.0.10492-ubuntu24.04
```

Then reconcile Flux:

```bash
export KUBECONFIG="$HOME/.kube/config.stage"
kubectl -n flux-system annotate kustomization apps reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite
kubectl -n flux-system wait kustomization/apps --for=condition=Ready --timeout=420s
```

### Validation in Kubernetes

```bash
export KUBECONFIG="$HOME/.kube/config.stage"
POD=$(kubectl -n default get pods -l app.kubernetes.io/name=plex -o jsonpath='{.items[0].metadata.name}')

# Test VAAPI transcoding
kubectl -n default exec "$POD" -- bash -c '
  "/usr/lib/plexmediaserver/Plex Transcoder" -v error \
    -f lavfi -i testsrc2=size=1920x1080:rate=30 -t 5 \
    -init_hw_device vaapi=va:/dev/dri/renderD128 \
    -vf format=nv12,hwupload \
    -c:v h264_vaapi \
    -f null - 2>&1 | tail -20
'
```

If successful, output should show:
- No "Failed to initialise VAAPI connection" error
- Successful encoding with `h264_vaapi` codec
- No I/O errors on `/dev/dri/renderD128`

## Dockerfile Strategy

The Dockerfile:
1. **Starts** with `lscr.io/linuxserver/plex:latest` (supports non-root UID 568)
2. **Installs** Ubuntu 24.04 libva/libdrm development libraries
3. **Backs up** original Plex bundled libraries for comparison
4. **Replaces** bundled `libva.so.2`, `libva-drm.so.2`, `libdrm.so.2`, `libdrm_intel.so.1` with system versions
5. **Ensures** symbolic links are correct
6. **Validates** via `vainfo` and `clinfo` installation
7. **Cleans** up build artifacts to keep image lean

## Expected Results

With this custom image deployed:
- ✅ Plex Transcoder VAAPI initialization should succeed
- ✅ Hardware video encoding (H.264, HEVC) should work
- ✅ Pod security policy compliance maintained (non-root, no privilege escalation)
- ✅ Device plugin GPU allocation working correctly
- ✅ No special host-level access required

## Troubleshooting

### If `vainfo` works but Plex Transcoder still fails
- Check Plex Transcoder binary release notes for VAAPI support status
- Verify Plex configuration has hardware acceleration enabled:
  ```bash
  kubectl -n default exec "$POD" -- grep -i "HardwareAccelerated" \
    /config/Library/Application\ Support/Plex\ Media\ Server/Preferences.xml || echo "Not enabled"
  ```

### If build fails with "package not found"
- Ubuntu 24.04 package names may have changed; check:
  ```bash
  apt-cache search libva | grep -i ubuntu
  ```

### If image is too large
- Remove build tools layer:
  ```dockerfile
  FROM builder AS runtime
  COPY --from=builder /usr/lib/plexmediaserver /usr/lib/plexmediaserver
  # ... minimal runtime setup
  ```

## References

- [Plex Media Server Transcoder Documentation](https://support.plex.tv/articles/200250387-transcoding/)
- [VA-API (libva) Documentation](https://github.com/intel/libva)
- [Intel iHD Driver](https://github.com/intel/media-driver)
- [Linuxserver Plex Image](https://docs.linuxserver.io/images/docker-plex/)
