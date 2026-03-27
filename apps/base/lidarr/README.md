# Lidarr (Base)

Base manifests for Lidarr music automation and library management.

## Purpose

- Captures common chart/release defaults used across environments.
- Defines baseline integration points with shared storage and indexers.
- Minimizes duplication in staging/prod overlays.

## In this folder

- Source/release resources and shared Kubernetes objects for Lidarr.

## Overlay expectations

- Environment-level endpoints, secrets, and scale values are applied in overlays.


## Parent/Siblings

- Parent: [Base](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Jellyfin](../jellyfin/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md).
