# Plex (Prod)

Production overlay for Plex.

## Purpose

- Runs Plex in the production Kubernetes cluster after migration from the legacy Proxmox LXC.
- Mirrors the legacy Plex media mounts at `/plex`, `/radarr`, and `/sonarr`.
- Pins Plex to Intel GPU-capable production workers via Node Feature Discovery labels and requests one `gpu.intel.com/i915` device for hardware transcoding.
- Uses the published `ghcr.io/richrobertson/plex-vaapi` image to keep VAAPI support working under Kubernetes.
- Exposes `plex.myrobertson.com` through the shared `myrobertson-com` Gateway listener on TLS port `443`.
- Keeps LAN split-DNS able to resolve `plex.myrobertson.com` to the internal gateway path while remote clients use public DNS.

## In this folder

- Prod-specific HelmRelease patching for Plex.
- Historical migration manifests retained in this folder but not included in steady-state kustomization.

## Operational notes

- Verified from a working prod media pod that writes to the scooter-backed Plex share succeed, but new files are created as uid/gid `568:568`.
- If scooter-side consumers still expect Synology ownership such as `99:100`, fix that on scooter with an ACL or ownership policy before final cutover.
- The public HTTPRoute depends on the `plex.myrobertson.com` listener in [infrastructure/gateway/myrobertson-com/myrobertson-com-gateway.yaml](../../../infrastructure/gateway/myrobertson-com/myrobertson-com-gateway.yaml).
- Do not reintroduce an `ADVERTISE_IP` override in Flux for prod Plex. On April 23-24, 2026, forcing custom advertised URLs caused `plex.myrobertson.com` requests on the shared gateway to stall/reset and broke local Shield playback until the override was removed and Plex restarted.
- When validating the shared gateway path from a shell, prefer `curl --http1.1 https://plex.myrobertson.com/identity`. On April 24, 2026, macOS `curl` negotiated HTTP/2 by default and still timed out even after the HTTP/1.1 gateway path and actual playback had recovered.

## Migration inputs

- Vault secret path: `secret/data/plex/prod/migration`
- Required keys: `host`, `username`, `sourcePath`, `sshPrivateKey`
- Optional keys: `port`, `knownHosts`
- Expected source path: the Plex LXC config directory, for example `/var/lib/plexmediaserver/Library/Application Support/Plex Media Server`
- The migration job writes to `/data/Library/Application Support/Plex Media Server` in the target PVC (the path expected by the container image).

Example Vault write:

```bash
vault kv put secret/plex/prod/migration \
	host="192.168.7.131" \
	port="22" \
	username="<lxc-ssh-user>" \
	sourcePath="/var/lib/plexmediaserver/Library/Application Support/Plex Media Server" \
	sshPrivateKey=@/path/to/id_ed25519 \
	knownHosts="$(ssh-keyscan -H 192.168.7.131 2>/dev/null)"
```

Verify Vault sync into Kubernetes:

```bash
kubectl --context=admin@prod get vaultstaticsecret -n default plex-lxc-migration -o wide
kubectl --context=admin@prod get secret -n default plex-lxc-migration -o jsonpath='{.metadata.name}{" keys="}{range $k,$v := .data}{$k}{" "}{end}{"\n"}'
```

## Scooter prep

- Confirm `/volume1/plex/4k` still exists on scooter and remains exported over NFS to the Kubernetes nodes.
- Ensure the export allows read/write from the cluster nodes without root squashing the app user into an unusable identity.
- If you want scooter-side ownership to stay Synology-native while Kubernetes writes as `568:568`, add an ACL on scooter that grants rwx to the effective Kubernetes write identity on `/volume1/plex`.
- Re-check from a cluster pod that `touch /media/4k/<tmpfile>` succeeds before cutover.

Cluster-side validation command:

```bash
POD=$(kubectl --context=admin@prod -n default get pods -l app.kubernetes.io/name=radarr -o jsonpath='{.items[0].metadata.name}')
kubectl --context=admin@prod -n default exec -c radarr "$POD" -- /bin/bash -lc 'touch /plex/4k/.permcheck && stat -c "%u %g %a %n" /plex/4k/.permcheck && rm -f /plex/4k/.permcheck'
```

## Migration flow

- Keep `Job/plex-config-seed-from-lxc` suspended in Git.
- Dry-run first by unsuspending with `DRY_RUN=true`.
- Run the real copy with `DRY_RUN=false` only after validating source path and target PVC contents.
- The real copy normalizes target ownership to `568:568` for the in-cluster Plex workload.

Dry-run:

```bash
kubectl --context=admin@prod patch job -n default plex-config-seed-from-lxc \
	--type merge \
	-p '{"spec":{"suspend":false,"template":{"spec":{"containers":[{"name":"seed","env":[{"name":"DRY_RUN","value":"true"},{"name":"ALLOW_NON_EMPTY_TARGET","value":"false"}]}]}}}}'

kubectl --context=admin@prod logs -n default job/plex-config-seed-from-lxc -f
```

Real copy:

```bash
kubectl --context=admin@prod delete job -n default plex-config-seed-from-lxc
kubectl --context=admin@prod apply -f apps/prod/plex/lxc-config-seed-job.yaml
kubectl --context=admin@prod patch job -n default plex-config-seed-from-lxc \
	--type merge \
	-p '{"spec":{"suspend":false,"template":{"spec":{"containers":[{"name":"seed","env":[{"name":"DRY_RUN","value":"false"},{"name":"ALLOW_NON_EMPTY_TARGET","value":"false"}]}]}}}}'

kubectl --context=admin@prod logs -n default job/plex-config-seed-from-lxc -f
kubectl --context=admin@prod get job -n default plex-config-seed-from-lxc
```
