# Custom Plex image that preserves Plex's bundled runtime ABI.
# Previous builds replaced bundled libdrm/libva and caused loader relocation errors
# (for example: __isoc23_* symbols not found). Keep bundled libs intact.

FROM alpine:3.21 AS musl_drivers

# Pull a coherent musl Intel VAAPI stack used only for driver artifacts.
RUN apk add --no-cache \
  intel-media-driver \
  libva-intel-driver \
  intel-gmmlib \
  libdrm \
  libva \
  libgcc \
  libstdc++

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

# Stage musl VAAPI runtime dependencies outside the default library path.
RUN mkdir -p /usr/lib/plexmediaserver/lib/vaapi-musl

COPY --from=musl_drivers /usr/lib/libstdc++.so.6 /usr/lib/plexmediaserver/lib/vaapi-musl/
COPY --from=musl_drivers /usr/lib/libgcc_s.so.1 /usr/lib/plexmediaserver/lib/vaapi-musl/
COPY --from=musl_drivers /usr/lib/libigdgmm.so.12 /usr/lib/plexmediaserver/lib/vaapi-musl/
COPY --from=musl_drivers /usr/lib/libdrm.so.2 /usr/lib/plexmediaserver/lib/vaapi-musl/
COPY --from=musl_drivers /usr/lib/libdrm_intel.so.1 /usr/lib/plexmediaserver/lib/vaapi-musl/

# Bake drivers into the same Conan-style locations referenced in Plex build metadata.
RUN mkdir -p \
  /home/runner/_work/plex-conan/plex-conan/.conan/data/intel-media-driver/25.2.6-1/plex/main/package/bb11b771bdd2e73dbca3ba3fa4e91df6e323972a/lib/dri \
  /home/runner/_work/plex-conan/plex-conan/.conan/data/intel-vaapi-driver/2.4.1-48/plex/main/package/54d41cda82931ea2b2be37156bad83b30007f4c5/lib/dri \
  /home/runner/_work/plex-conan/plex-conan/.conan/data/libva/2.22.0-0/plex/main/build/f0f4893209b867ce448a96e25ef4d6b158311557/install/lib/dri

COPY --from=musl_drivers /usr/lib/dri/iHD_drv_video.so /home/runner/_work/plex-conan/plex-conan/.conan/data/intel-media-driver/25.2.6-1/plex/main/package/bb11b771bdd2e73dbca3ba3fa4e91df6e323972a/lib/dri/
COPY --from=musl_drivers /usr/lib/dri/i965_drv_video.so /home/runner/_work/plex-conan/plex-conan/.conan/data/intel-vaapi-driver/2.4.1-48/plex/main/package/54d41cda82931ea2b2be37156bad83b30007f4c5/lib/dri/
COPY --from=musl_drivers /usr/lib/dri/iHD_drv_video.so /home/runner/_work/plex-conan/plex-conan/.conan/data/libva/2.22.0-0/plex/main/build/f0f4893209b867ce448a96e25ef4d6b158311557/install/lib/dri/
COPY --from=musl_drivers /usr/lib/dri/i965_drv_video.so /home/runner/_work/plex-conan/plex-conan/.conan/data/libva/2.22.0-0/plex/main/build/f0f4893209b867ce448a96e25ef4d6b158311557/install/lib/dri/

# Keep bundled Plex libraries first while making musl driver deps available.
ENV LD_LIBRARY_PATH=/usr/lib/plexmediaserver/lib:/usr/lib/plexmediaserver/lib/vaapi-musl

# Keep a record of runtime and bundled libraries for troubleshooting.
RUN ldd --version > /image-libc.txt 2>&1 || true && \
  find /usr/lib/plexmediaserver/lib -maxdepth 1 -type f -name "*.so*" | sort > /plex-bundled-libs.txt

LABEL org.opencontainers.image.description="Plex Media Server image preserving bundled ABI with VAAPI tooling"
LABEL com.example.built-for="staging-kubernetes-vaapi"
