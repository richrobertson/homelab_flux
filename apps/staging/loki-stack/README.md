# Loki Stack (Staging)

Staging overlay for logging stack components.

## Purpose

- Validates log ingestion and query behavior before production changes.
- Applies staging-specific retention/performance values over base manifests.

## In this folder

- Staging patches and kustomization wiring for Loki stack resources.

## Typical staging deltas

- Lower retention windows, reduced storage footprint, and sandbox labels.


## Parent/Siblings

- Parent: [Staging](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Lidarr](../lidarr/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md).
