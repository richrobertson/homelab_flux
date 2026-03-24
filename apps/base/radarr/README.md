# Radarr (Base)

Base manifests for Radarr movie automation services.

## Purpose

- Defines common chart source and default release values.
- Maintains shared app integration assumptions and storage patterns.
- Enables lean staging/prod overlays focused on deltas.

## In this folder

- Helm source/release resources and shared Radarr manifests.

## Overlay expectations

- Environment-specific endpoints, secrets, and sizing are set by overlays.


## Parent/Siblings

- Parent: [Base](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Jellyfin](../jellyfin/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md); [Whisparr](../whisparr/README.md).
