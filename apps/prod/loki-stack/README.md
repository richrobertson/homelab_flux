# Loki Stack (Prod)

Production overlay for logging stack resources.

## Purpose

- Provides production-grade logging retention and query behavior.
- Applies storage/performance tuning over the Loki base layer.

## In this folder

- Production patches and kustomization entries for log platform components.

## Typical production deltas

- Higher retention, larger persistent volumes, and production scrape/label tuning.


## Parent/Siblings

- Parent: [Prod](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Lidarr](../lidarr/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [Whisparr](../whisparr/README.md).
