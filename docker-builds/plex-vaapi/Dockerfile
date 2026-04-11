# Custom Plex image built from the official Plex Ubuntu image so the Plex runtime,
# libc, and Intel VAAPI userspace all come from the same glibc world.

ARG PLEX_BASE_IMAGE=plexinc/pms-docker:1.43.1.10611-1e34174b1
FROM ${PLEX_BASE_IMAGE}

# Install Intel VAAPI userspace from the same Ubuntu base as the official image.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  vainfo \
  clinfo \
  libdrm2 \
  libdrm-intel1 \
  libva2 \
  libva-drm2 \
  intel-media-va-driver \
  && rm -rf /var/lib/apt/lists/*

# Capture runtime facts used during staged validation.
RUN ldd --version > /image-libc.txt 2>&1 || true && \
  find /usr/lib/plexmediaserver -maxdepth 2 -type f \( -name "Plex Transcoder" -o -name "*.so*" \) | sort > /plex-runtime-libs.txt && \
  find /usr/lib -path "*/dri/*drv_video.so" | sort > /vaapi-driver-paths.txt

LABEL org.opencontainers.image.description="Plex Media Server image derived from the official glibc-based Plex image with Intel VAAPI tooling"
LABEL com.example.built-for="staging-kubernetes-vaapi"
