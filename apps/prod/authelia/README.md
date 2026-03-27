# Authelia (Prod)

Production overlay for Authelia.

## Purpose

- Applies production auth settings over `apps/base/authelia`.
- Hosts live identity/access behavior for protected services.

## In this folder

- Production patches, kustomization entries, and references to prod secrets.

## Current cutover state

- Production enables `../../base/authelia/release-ceph-cutover.yaml`.
- Production deletes the legacy `cluster-authelia` CNPG cluster so Flux does not recreate it after cleanup.
- Authelia in prod targets `cluster-authelia-ceph` and reads the database password from the CNPG-generated `cluster-authelia-ceph-app` secret.

## Typical production deltas

- Canonical domains, strict policy values, and production-grade resources.


## Parent/Siblings

- Parent: [Prod](../README.md)
- Siblings: [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md).
