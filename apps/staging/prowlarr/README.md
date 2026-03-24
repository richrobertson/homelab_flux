# Prowlarr (Staging)

Staging overlay for Prowlarr.

## Purpose

- Tests indexer and release configuration changes before production.
- Applies staging values over `apps/base/prowlarr`.

## In this folder

- Staging kustomization references and patch manifests.

## Typical staging deltas

- Non-prod API keys, sandbox integrations, and lower resource limits.


## Parent/Siblings

- Parent: [Staging](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md); [Whisparr](../whisparr/README.md).
