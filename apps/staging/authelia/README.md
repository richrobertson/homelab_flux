# Authelia (Staging)

Staging overlay for Authelia.

## Purpose

- Applies staging-specific patches on top of `apps/base/authelia`.
- Validates auth flow and integration changes before production promotion.

## In this folder

- Kustomization references and patch manifests for staging-only values.

## Typical staging deltas

- Sandbox hostnames, reduced scale, and non-production secret references.


## Parent/Siblings

- Parent: [Staging](../README.md)
- Siblings: [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md); [Whisparr](../whisparr/README.md).
