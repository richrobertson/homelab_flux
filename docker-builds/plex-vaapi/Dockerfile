# Custom Plex Media Server image with Ubuntu 24.04-compatible VAAPI libraries
# This resolves ABI incompatibilities between Plex's bundled libc/libva/libdrm and system drivers
# Base: linuxserver/plex (supports non-root UID 568)
# Target: x86_64 with Intel iHD VAAPI support via device plugin

FROM lscr.io/linuxserver/plex:latest as base

# Install build tools and Ubuntu 24.04 libva/libdrm development packages
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    python3 \
    wget \
    curl \
    ca-certificates \
    intel-media-va-driver \
    libva-dev \
    libva-drm2 \
    libva-x11-2 \
    libdrm-dev \
    libdrm2 \
    libdrm-intel1 \
    xorg-sgml-doctools \
    x11proto-dev \
    libx11-dev \
    && rm -rf /var/lib/apt/lists/*

# Extract bundled libs from Plex to inspect
RUN mkdir -p /plex-libs-orig && \
    find /usr/lib/plexmediaserver/lib -type f -name "*.so*" | head -20 > /tmp/bundled-libs.txt

# Backup original bundled libraries
RUN mkdir -p /bundled-backup && \
    cp -r /usr/lib/plexmediaserver/lib/* /bundled-backup/ 2>/dev/null || true

# Create system library wrapper directory
RUN mkdir -p /usr/lib/plexmediaserver/lib-system && \
    cp /usr/lib/x86_64-linux-gnu/libva.so.2 /usr/lib/plexmediaserver/lib-system/ 2>/dev/null || true && \
    cp /usr/lib/x86_64-linux-gnu/libva-drm.so.2 /usr/lib/plexmediaserver/lib-system/ 2>/dev/null || true && \
    cp /usr/lib/x86_64-linux-gnu/libva-x11.so.2 /usr/lib/plexmediaserver/lib-system/ 2>/dev/null || true && \
    cp /usr/lib/x86_64-linux-gnu/libdrm.so.2 /usr/lib/plexmediaserver/lib-system/ 2>/dev/null || true && \
    cp /usr/lib/x86_64-linux-gnu/libdrm_intel.so.1 /usr/lib/plexmediaserver/lib-system/ 2>/dev/null || true

# Update bundled libva/libdrm with system versions that match Ubuntu 24.04
# This ensures ABI compatibility with the iHD driver loaded from system paths
RUN if [ -f /usr/lib/x86_64-linux-gnu/libva.so.2 ]; then \
      cp /usr/lib/x86_64-linux-gnu/libva.so.2 /usr/lib/plexmediaserver/lib/libva.so.2 && \
      ln -sf libva.so.2 /usr/lib/plexmediaserver/lib/libva.so; \
    fi && \
    if [ -f /usr/lib/x86_64-linux-gnu/libva-drm.so.2 ]; then \
      cp /usr/lib/x86_64-linux-gnu/libva-drm.so.2 /usr/lib/plexmediaserver/lib/libva-drm.so.2 && \
      ln -sf libva-drm.so.2 /usr/lib/plexmediaserver/lib/libva-drm.so; \
    fi && \
    if [ -f /usr/lib/x86_64-linux-gnu/libdrm.so.2 ]; then \
      cp /usr/lib/x86_64-linux-gnu/libdrm.so.2 /usr/lib/plexmediaserver/lib/libdrm.so.2 && \
      ln -sf libdrm.so.2 /usr/lib/plexmediaserver/lib/libdrm.so; \
    fi && \
    if [ -f /usr/lib/x86_64-linux-gnu/libdrm_intel.so.1 ]; then \
      cp /usr/lib/x86_64-linux-gnu/libdrm_intel.so.1 /usr/lib/plexmediaserver/lib/libdrm_intel.so.1; \
    fi

# Update library cache in case Plex checks ld.so
RUN ldconfig 2>/dev/null || true

# Install vainfo for debugging/validation
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    vainfo clinfo \
    && rm -rf /var/lib/apt/lists/*

# Clean up build artifacts to keep image size reasonable
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Label for tracking
LABEL org.opencontainers.image.description="Plex Media Server with Ubuntu 24.04 VAAPI libraries for Intel iGPU hardware transcoding"
LABEL com.example.built-for="staging-kubernetes-vaapi"
