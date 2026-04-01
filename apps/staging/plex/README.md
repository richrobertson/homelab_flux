# Plex (Staging)

Staging overlay for Plex.

## Purpose

- Tests Plex in staging before any production rollout.
- Mounts NFS export `/volume1/plex` from scooter and uses the `4k` subfolder in Plex.
- Keeps hardware transcoding enabled through `/dev/dri` passthrough.
- Exposes Plex at `https://plex.staging.myrobertson.net` on the staging local network.
