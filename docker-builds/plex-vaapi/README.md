# Custom Plex VAAPI Image Build

## Problem Statement

The previous custom image strategy kept Plex on the linuxserver.io image line and attempted to reconcile VAAPI by mixing Plex's bundled userspace with distro Intel drivers. That left Plex Transcoder in a musl-based runtime while the Intel iHD driver came from Ubuntu's glibc userspace, which produced loader failures during VAAPI initialization.

## Solution

Build the custom image from the official Plex Docker image line instead:

- Base image: `plexinc/pms-docker`
- Runtime world: Ubuntu 24.04 + glibc throughout
- VAAPI userspace: distro `libva`, `libdrm`, and `intel-media-va-driver`

This keeps the Plex runtime and the Intel driver stack in one ABI family and avoids the mixed musl/glibc loader path that blocked hardware initialization.

## Build Instructions

### Prerequisites

- Docker or Podman installed
- Access to container registry (`oci.trueforge.org/homelab/plex-vaapi`)
- ~2GB disk space for build

### Build Locally

```bash
cd docker-builds/plex-vaapi
chmod +x build-plex-vaapi.sh
./build-plex-vaapi.sh --tag v1.43.1.10611-officialglibc1
```

### Build and Push to Registry

```bash
./build-plex-vaapi.sh --push --tag v1.43.1.10611-officialglibc1
```

### Manual Build (Docker)

```bash
cd docker-builds/plex-vaapi
docker build -t ghcr.io/richrobertson/plex-vaapi:v1.43.1.10611-officialglibc1 .
docker push ghcr.io/richrobertson/plex-vaapi:v1.43.1.10611-officialglibc1
```

## Testing the Custom Image

### Local Validation

```bash
docker run --rm -it ghcr.io/richrobertson/plex-vaapi:v1.43.1.10611-officialglibc1 bash

# Inside container:
vainfo --display drm --device /dev/dri/renderD128  # Should show VA-API + iHD
"/usr/lib/plexmediaserver/Plex Transcoder" -hwaccels  # Should list vaapi
```

### Kubernetes Deployment

Update [plex-values.yaml](../../apps/staging/plex/plex-values.yaml):

```yaml
image:
  repository: ghcr.io/richrobertson/plex-vaapi
  tag: v1.43.1.10611-officialglibc1
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

The Dockerfile now:
1. Starts with a version-pinned `plexinc/pms-docker` image.
2. Installs Ubuntu VAAPI tooling from the same glibc-based distro layer.
3. Leaves Plex's own runtime layout intact instead of swapping individual shared libraries.
4. Records runtime library and driver paths for post-build inspection.

## Expected Results

With this custom image deployed:
- Expected: Plex runtime and Intel VAAPI userspace no longer cross libc families.
- Expected: the staging pod can initialize VAAPI without the `__isoc23_*` relocation failures seen in the previous image line.
- Validation still required in-cluster because actual hardware transcode enablement also depends on Plex app settings and Plex Pass state.

## Troubleshooting

### If `vainfo` works but Plex Transcoder still fails
- Verify Plex configuration has hardware acceleration enabled:
  ```bash
  kubectl -n default exec "$POD" -- grep -i "HardwareAccelerated" \
    /config/Library/Application\ Support/Plex\ Media\ Server/Preferences.xml || echo "Not enabled"
  ```

### If build fails with "package not found"
- The upstream official image is Ubuntu-based; confirm package names in the current release:
  ```bash
  apt-cache search libva
  ```

### If the upstream Plex version must be pinned differently
- Override the Docker build arg:
  ```bash
  docker build \
    --build-arg PLEX_BASE_IMAGE=plexinc/pms-docker:public \
    -t ghcr.io/richrobertson/plex-vaapi:test .
  ```

## References

- [Plex Media Server Transcoder Documentation](https://support.plex.tv/articles/200250387-transcoding/)
- [VA-API (libva) Documentation](https://github.com/intel/libva)
- [Intel iHD Driver](https://github.com/intel/media-driver)
- [Linuxserver Plex Image](https://docs.linuxserver.io/images/docker-plex/)
