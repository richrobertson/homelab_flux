# Plex (Prod)

Production overlay for Plex.

## Purpose

- Stages Plex in the production Kubernetes cluster while migration from the legacy Proxmox LXC is prepared.
- Leaves public traffic on the legacy Proxmox LXC route until final cutover.
- Keeps the existing scooter NFS media mapping at `/volume1/plex/4k -> /media/4k`.
- Keeps `/dev/dri` disabled because production rollout is not using hardware transcoding.

## In this folder

- Prod-specific HelmRelease patching for Plex before cutover.
- A suspended config migration job and Vault-backed migration secret.

## Operational notes

- Keep replicas at `0` until the Plex config data has been copied into `plex-config-ceph` and validated.
- Do not change the gateway or `HTTPRoute` until the in-cluster deployment has been validated.
- Add the in-cluster `HTTPRoute` and remove the legacy Proxmox/LXC external route in the same final cutover commit.
- Verified from a working prod media pod that writes to the scooter-backed Plex share succeed, but new files are created as uid/gid `568:568`.
- If scooter-side consumers still expect Synology ownership such as `99:100`, fix that on scooter with an ACL or ownership policy before final cutover.

## Migration inputs

- Vault secret path: `secret/data/plex/prod/migration`
- Required keys: `host`, `username`, `sourcePath`, `sshPrivateKey`
- Optional keys: `port`, `knownHosts`
- Expected source path: the Plex LXC config directory, for example `/var/lib/plexmediaserver/Library/Application Support/Plex Media Server`

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
