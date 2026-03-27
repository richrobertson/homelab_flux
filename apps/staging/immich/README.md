# Immich (Staging)

Staging overlay for Immich.

## Purpose

- Validates Immich upgrades and config changes prior to production rollout.
- Applies environment-specific settings over `apps/base/immich`.

## In this folder

- Staging patch resources, kustomization wiring, and optional test-safe values.

## Typical staging deltas

- Reduced resource requests, non-prod ingress hosts, and staging storage references.


## Parent/Siblings

- Parent: [Staging](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md).
