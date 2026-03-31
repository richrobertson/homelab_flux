# Apps Prod

`apps/prod/` defines environment-specific overlays for the production cluster.

## Purpose

- Applies production-grade values and patches on top of `apps/base/`.
- Hosts stable, validated app configuration intended for daily use.
- Serves as the final target of promotion from staging.

## What belongs here

- Production-specific patches, values files, and app kustomizations.
- Stronger availability/resource settings (for example replicas, persistence, retention).
- Production ingress, hostnames, and integration references.

## Promotion model

1. Validate base/overlay changes in staging.
2. Promote equivalent changes into production overlays.
3. Reconcile Flux and confirm health/metrics post-deploy.

## Change guardrails

- Keep production-only deltas explicit and reviewable.
- Avoid introducing breaking drift between staging and prod unless required.
- Record major behavior differences in PR descriptions for auditability.

## See also

- [Apps overview](../README.md)
- [Shared base layer](../base/README.md)
- [Staging overlays](../staging/README.md)

Leaf docs:

- [Authelia production](authelia/README.md)
- [External DNS production](external-dns/README.md)
- [Immich production](immich/README.md)
- [Lidarr production](lidarr/README.md)
- [Loki Stack (Prod)](loki-stack/README.md)
- [Mealie production](mealie/README.md)
- [Overseerr production](overseerr/README.md)
- [Prowlarr production](prowlarr/README.md)
- [Radarr production](radarr/README.md)
- [Shared Storage (Prod)](shared_storage/README.md)
- [Sonarr production](sonarr/README.md)
- [Syncthing production](syncthing/README.md)
- [VolSync production](volsync/README.md)