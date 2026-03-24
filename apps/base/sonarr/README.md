# Sonarr (Base)

Base manifests for Sonarr TV automation and library management.

## Purpose

- Maintains default chart source/release settings shared by environments.
- Defines core app assumptions for storage and service behavior.
- Supports consistent promotion from staging to production.

## In this folder

- Helm source/release resources and common Sonarr manifests.

## Overlay expectations

- Environment-specific secrets, route details, and scale settings are patched in overlays.


## Parent/Siblings

- Parent: [Base](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Jellyfin](../jellyfin/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md); [Whisparr](../whisparr/README.md).
