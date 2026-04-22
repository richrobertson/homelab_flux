# Plex (Staging)

Staging overlay for Plex.

## Purpose

- Tests Plex in staging before any production rollout.
- Mounts NFS export `/volume1/plex` from scooter and uses the `4k` subfolder in Plex.
- Uses the standard Plex chart image path without dedicated GPU scheduling so staging stays lightweight and avoids competing with production for host iGPU access.
- Exposes Plex at `https://plex.staging.myrobertson.net` on the staging local network.
