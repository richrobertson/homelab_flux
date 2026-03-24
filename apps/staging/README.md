# Apps Staging

`apps/staging/` defines environment-specific overlays for the staging cluster.

## Purpose

- Applies staging-safe values and patches on top of `apps/base/`.
- Enables validation of app changes before production rollout.
- Supports lower-risk experimentation for chart/version changes.

## What belongs here

- Kustomization entries that include or patch base app resources.
- Staging-only values such as reduced replicas, sandbox hostnames, and lower resource requests.
- Optional staging-only app inclusion/exclusion decisions.

## Operational intent

- Staging should remain production-like enough to catch deployment issues.
- Differences from production should be intentional and minimal.
- Use this layer to prove upgrades before promoting to `apps/prod/`.

## Current app subsets

Includes overlays for core homelab services such as auth, DNS, observability, media automation, sync, and storage support.

## See also

- [Apps overview](../README.md)
- [Shared base layer](../base/README.md)
- [Production overlays](../prod/README.md)

Leaf docs:

- [Authelia staging](authelia/README.md)
- [External DNS staging](external-dns/README.md)
- [Immich staging](immich/README.md)
- [Lidarr staging](lidarr/README.md)
- [Loki stack staging](loki-stack/README.md)
- [Mealie staging](mealie/README.md)
- [Overseerr staging](overseerr/README.md)
- [Prowlarr staging](prowlarr/README.md)
- [Radarr staging](radarr/README.md)
- [Shared storage staging](shared_storage/README.md)
- [Sonarr staging](sonarr/README.md)
- [Syncthing staging](syncthing/README.md)
- [VolSync staging](volsync/README.md)
- [Whisparr staging](whisparr/README.md)