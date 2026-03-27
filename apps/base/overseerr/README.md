# Overseerr (Base)

Base manifests for Overseerr media request workflows.

## Purpose

- Establishes default source/release settings shared by all environments.
- Provides baseline service behavior and integration points.
- Reduces environment duplication through a single reusable base.

## In this folder

- Helm source/release resources and shared Kubernetes app manifests.

## Overlay expectations

- Environment credentials, hostnames, and resource tuning are patched in overlays.


## Parent/Siblings

- Parent: [Base](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Jellyfin](../jellyfin/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md).
