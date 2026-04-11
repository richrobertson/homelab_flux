# Custom Plex image that preserves Plex's bundled runtime ABI.
# Previous builds replaced bundled libdrm/libva and caused loader relocation errors
# (for example: __isoc23_* symbols not found). Keep bundled libs intact.

FROM lscr.io/linuxserver/plex:latest as base

# Install only diagnostic tools and avoid replacing bundled Plex shared libraries.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  vainfo \
  clinfo \
  libdrm2 \
  libdrm-intel1 \
  libva2 \
  libva-drm2 \
  intel-media-va-driver \
  && rm -rf /var/lib/apt/lists/*

# Keep a record of runtime and bundled libraries for troubleshooting.
RUN ldd --version > /image-libc.txt 2>&1 || true && \
  find /usr/lib/plexmediaserver/lib -maxdepth 1 -type f -name "*.so*" | sort > /plex-bundled-libs.txt

LABEL org.opencontainers.image.description="Plex Media Server image preserving bundled ABI with VAAPI tooling"
LABEL com.example.built-for="staging-kubernetes-vaapi"
