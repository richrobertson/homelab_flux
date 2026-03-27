# VolSync (Staging)

Staging overlay for VolSync replication workflows.

## Purpose

- Tests replication schedules/targets before production promotion.
- Applies staging-specific policy and credential variance over base VolSync config.

## In this folder

- Overlay patches and kustomization wiring for staging sync behavior.

## Typical staging deltas

- Test destinations, relaxed intervals, and non-production secret references.


## Parent/Siblings

- Parent: [Staging](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md).
