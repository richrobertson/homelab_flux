# Sonarr (Staging)

Staging overlay for Sonarr.

## Purpose

- Validates TV automation behavior and chart upgrades prior to production.
- Applies staging-specific differences over `apps/base/sonarr`.

## In this folder

- Overlay patches and kustomization references.

## Typical staging deltas

- Sandbox connectivity, reduced resources, and non-production secrets.


## Parent/Siblings

- Parent: [Staging](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md).
