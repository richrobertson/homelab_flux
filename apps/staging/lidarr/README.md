# Lidarr (Staging)

Staging overlay for Lidarr.

## Purpose

- Proves automation and chart changes safely before production use.
- Extends `apps/base/lidarr` with staging-specific configuration.

## In this folder

- Overlay patches and staging kustomization entries.

## Typical staging deltas

- Non-production endpoints, constrained resources, and test credentials.


## Parent/Siblings

- Parent: [Staging](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md).
