# Nextcloud Migration Overlays

This directory holds disabled, review-only patches for the future cutover from AWS S3 primary object storage to filesystem-backed data on Synology NFS.

Do not add `synology-filesystem-data-pvc.patch.yaml` to production until a dry run has passed and the production cutover window has started. The current production overlay still adds AWS S3 primary object storage, and this PR intentionally does not remove it.

Important namespace constraint: the staged target PVC is `nextcloud/nextcloud-data`, while the current HelmRelease is rendered into the `default` namespace. Kubernetes PVC mounts are namespace-scoped. A later explicit cutover PR must either move the Nextcloud workload to the `nextcloud` namespace or create an equivalent same-namespace claim for the workload namespace.
