# VolSync (Staging)

Staging overlay for VolSync replication workflows.

## Purpose

- Tests replication schedules/targets before production promotion.
- Applies staging-specific policy and credential variance over base VolSync config.

## In this folder

- Overlay patches and kustomization wiring for staging sync behavior.

## Typical staging deltas

- Test destinations, relaxed intervals, and non-production secret references.

## Current backup policy

Staging VolSync ReplicationSource policy is defined in [infrastructure/configs/volsync/replicationsources.yaml](/Users/rich/Documents/GitHub/homelab_flux/infrastructure/configs/volsync/replicationsources.yaml):

- schedule: every hour at the source's assigned minute offset
- hourly: 4
- daily: 0
- weekly: 0
- monthly: 0
- pruneIntervalDays: 1

Policy intent:

- Run each protected PVC backup once per hour.
- Keep only the latest 4 hourly snapshots per repository.
- Prune daily so expired hourly snapshots are reclaimed promptly.


## Parent/Siblings

- Parent: [Staging](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md).
