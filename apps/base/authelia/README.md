# Authelia (Base)

Base manifests for the Authelia identity and access control service.

## Purpose

- Defines the shared Helm source and default release settings.
- Establishes common dependencies such as namespace/secret references and backing services.
- Provides the baseline consumed by staging and production overlays.

## In this folder

- Repository and release definitions for Authelia.
- Shared manifests that should not vary by environment unless explicitly patched.

## Overlay expectations

- Keep secure and environment-specific endpoints in `apps/staging/authelia` and `apps/prod/authelia`.


## Parent/Siblings

- Parent: [Base](../README.md)
- Siblings: [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Jellyfin](../jellyfin/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md); [Whisparr](../whisparr/README.md).
