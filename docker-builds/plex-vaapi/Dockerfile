# Custom Plex image that keeps Plex's bundled runtime intact while using
# distro-native glibc Intel VAAPI drivers.

FROM ghcr.io/linuxserver/ffmpeg:latest AS ffmpeg_drivers

FROM lscr.io/linuxserver/plex:latest as base

# Install only diagnostic tools and avoid replacing bundled Plex shared libraries.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  vainfo \
  clinfo \
  ffmpeg \
  libdrm2 \
  libdrm-intel1 \
  libigdgmm12 \
  libva2 \
  libva-drm2 \
  && rm -rf /var/lib/apt/lists/*

# Bake drivers into the same Conan-style locations referenced in Plex build metadata.
RUN mkdir -p \
  /home/runner/_work/plex-conan/plex-conan/.conan/data/intel-media-driver/25.2.6-1/plex/main/package/bb11b771bdd2e73dbca3ba3fa4e91df6e323972a/lib/dri \
  /home/runner/_work/plex-conan/plex-conan/.conan/data/intel-vaapi-driver/2.4.1-48/plex/main/package/54d41cda82931ea2b2be37156bad83b30007f4c5/lib/dri \
  /home/runner/_work/plex-conan/plex-conan/.conan/data/libva/2.22.0-0/plex/main/build/f0f4893209b867ce448a96e25ef4d6b158311557/install/lib/dri

# Import known-good VAAPI drivers from linuxserver/ffmpeg image.
COPY --from=ffmpeg_drivers /usr/local/lib/x86_64-linux-gnu/dri/iHD_drv_video.so /tmp/ffmpeg-dri/iHD_drv_video.so
COPY --from=ffmpeg_drivers /usr/local/lib/x86_64-linux-gnu/dri/i965_drv_video.so /tmp/ffmpeg-dri/i965_drv_video.so

RUN set -eux; \
  cp -f /tmp/ffmpeg-dri/iHD_drv_video.so \
    /usr/lib/x86_64-linux-gnu/dri/; \
  cp -f /tmp/ffmpeg-dri/i965_drv_video.so \
    /usr/lib/x86_64-linux-gnu/dri/; \
  cp -f /tmp/ffmpeg-dri/iHD_drv_video.so \
    /home/runner/_work/plex-conan/plex-conan/.conan/data/intel-media-driver/25.2.6-1/plex/main/package/bb11b771bdd2e73dbca3ba3fa4e91df6e323972a/lib/dri/; \
  cp -f /tmp/ffmpeg-dri/i965_drv_video.so \
    /home/runner/_work/plex-conan/plex-conan/.conan/data/intel-vaapi-driver/2.4.1-48/plex/main/package/54d41cda82931ea2b2be37156bad83b30007f4c5/lib/dri/; \
  cp -f /tmp/ffmpeg-dri/iHD_drv_video.so \
    /home/runner/_work/plex-conan/plex-conan/.conan/data/libva/2.22.0-0/plex/main/build/f0f4893209b867ce448a96e25ef4d6b158311557/install/lib/dri/; \
  cp -f /tmp/ffmpeg-dri/i965_drv_video.so \
    /home/runner/_work/plex-conan/plex-conan/.conan/data/libva/2.22.0-0/plex/main/build/f0f4893209b867ce448a96e25ef4d6b158311557/install/lib/dri/

# Prefer distro driver directory for explicit probes and debugging.
ENV LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri
ENV LIBVA_DRIVER_NAME=iHD

# Keep a record of runtime and bundled libraries for troubleshooting.
RUN ldd --version > /image-libc.txt 2>&1 || true && \
  find /usr/lib/plexmediaserver/lib -maxdepth 1 -type f -name "*.so*" | sort > /plex-bundled-libs.txt

LABEL org.opencontainers.image.description="Plex Media Server image preserving bundled ABI with VAAPI tooling"
LABEL com.example.built-for="staging-kubernetes-vaapi"
