# Shared Storage (Base)

Base manifests for storage resources consumed by multiple applications.

## Purpose

- Defines reusable PVC/storage-related resources for cross-app use.
- Centralizes storage baseline settings for consistent behavior.
- Prevents per-app duplication of common storage primitives.

## In this folder

- Shared storage manifests and references used by app releases.

## Overlay expectations

- Capacity classes or environment-specific storage bindings can be patched in overlays.


## Parent/Siblings

- Parent: [Base](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Jellyfin](../jellyfin/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md); [Whisparr](../whisparr/README.md).
