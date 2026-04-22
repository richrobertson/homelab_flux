# Plex (Staging)

Staging overlay for Plex.

## Purpose

- Tests Plex in staging before any production rollout.
- Mounts NFS export `/volume1/plex` from scooter and uses the `4k` subfolder in Plex.
- Uses the published `ghcr.io/richrobertson/plex-vaapi` image and schedules onto the Intel GPU worker via Node Feature Discovery labels.
- Requests one `gpu.intel.com/i915` device so the Intel device plugin can expose hardware transcoding support.
- Exposes Plex at `https://plex.staging.myrobertson.net` on the staging local network.
