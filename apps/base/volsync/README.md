# VolSync (Base)

Base manifests for VolSync volume replication and synchronization.

## Purpose

- Defines common source/release settings for volume sync workflows.
- Provides shared synchronization primitives usable across environments.
- Establishes defaults that overlays can tune per environment.

## In this folder

- Helm source/release and shared sync-related resources.

## Overlay expectations

- Environment schedules, destinations, and credential references are patched in overlays.


## Parent/Siblings

- Parent: [Base](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Jellyfin](../jellyfin/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md).
