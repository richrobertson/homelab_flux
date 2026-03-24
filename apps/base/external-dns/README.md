# External DNS (Base)

Base manifests for ExternalDNS, which syncs Kubernetes records into DNS providers.

## Purpose

- Declares common chart source and baseline release configuration.
- Defines shared controller behavior used in all environments.
- Serves as the canonical source for DNS automation defaults.

## In this folder

- Helm repository/release resources and shared supporting objects.

## Overlay expectations

- Environment credentials and provider-specific variance belong in environment overlays.


## Parent/Siblings

- Parent: [Base](../README.md)
- Siblings: [Authelia](../authelia/README.md); [Immich](../immich/README.md); [Jellyfin](../jellyfin/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md); [Whisparr](../whisparr/README.md).
