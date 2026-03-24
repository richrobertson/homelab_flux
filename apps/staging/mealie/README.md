# Mealie (Staging)

Staging overlay for Mealie.

## Purpose

- Tests release/value updates for recipe services prior to production.
- Applies staging-specific settings over `apps/base/mealie`.

## In this folder

- Overlay patches and kustomization references for staging.

## Typical staging deltas

- Sandbox hostnames, smaller resources, and non-production secrets.


## Parent/Siblings

- Parent: [Staging](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md); [Whisparr](../whisparr/README.md).
