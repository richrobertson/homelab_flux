# Whisparr (Staging)

Staging overlay for Whisparr.

## Purpose

- Validates release/configuration changes safely before production.
- Applies staging-specific values on top of the base Whisparr manifests.

## In this folder

- Staging patches and overlay kustomization resources.

## Typical staging deltas

- Sandbox hostnames, reduced resources, and test secret references.


## Parent/Siblings

- Parent: [Staging](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md).
