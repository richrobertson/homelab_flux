#!/usr/bin/env bash
set -euo pipefail

if [[ -f "${HOME}/.bash_profile" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.bash_profile" >/dev/null 2>&1
fi

umask 077

KUBE_CONTEXT="${KUBE_CONTEXT:-admin@prod}"
NAMESPACE="${NAMESPACE:-default}"
DEPLOYMENT="${DEPLOYMENT:-nextcloud}"
NEXTCLOUD_CONTAINER="${NEXTCLOUD_CONTAINER:-nextcloud}"
CNPG_CLUSTER="${CNPG_CLUSTER:-nextcloud-cnpg}"
CNPG_APP_SECRET="${CNPG_APP_SECRET:-nextcloud-cnpg-app}"
S3_SECRET="${S3_SECRET:-nextcloud-s3-secret}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/nextcloud-prod-backup-capture-$(date +%Y%m%d-%H%M%S)}"
S3_INVENTORY_ENABLED="${S3_INVENTORY_ENABLED:-true}"
VERIFY_DB_DUMP="${VERIFY_DB_DUMP:-true}"

SECRET_NAMES=(${SECRET_NAMES:-nextcloud-secret nextcloud-s3-secret nextcloud-ldap-secret collabora-secret nextcloud-cnpg-app})
RESOURCE_NAMES=(${RESOURCE_NAMES:-helmrelease/nextcloud cluster/nextcloud-cnpg scheduledbackup/nextcloud-cnpg-daily deploy/nextcloud pvc/nextcloud-data-pvc-ceph-v2})

mkdir -p \
  "${OUTPUT_DIR}/database" \
  "${OUTPUT_DIR}/kubernetes/secrets" \
  "${OUTPUT_DIR}/kubernetes/resources" \
  "${OUTPUT_DIR}/nextcloud" \
  "${OUTPUT_DIR}/s3"

section() {
  printf '\n== %s ==\n' "$1"
}

write_manifest() {
  local resource="$1"
  local output="$2"

  if kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get "${resource}" -o yaml >"${output}" 2>/dev/null; then
    printf 'captured=%s\n' "${output}"
  else
    printf 'missing_resource=%s\n' "${resource}" | tee -a "${OUTPUT_DIR}/warnings.txt"
  fi
}

echo "Nextcloud production backup capture"
echo "context=${KUBE_CONTEXT}"
echo "namespace=${NAMESPACE}"
echo "deployment=${DEPLOYMENT}"
echo "output_dir=${OUTPUT_DIR}"
echo "printed_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "sensitive_output=true"

section "nextcloud status"
kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" exec "deploy/${DEPLOYMENT}" -c "${NEXTCLOUD_CONTAINER}" -- \
  php occ status | tee "${OUTPUT_DIR}/nextcloud/status.txt"
kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" exec "deploy/${DEPLOYMENT}" -c "${NEXTCLOUD_CONTAINER}" -- \
  php occ encryption:status | tee "${OUTPUT_DIR}/nextcloud/encryption-status.txt"

section "config.php"
kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" exec "deploy/${DEPLOYMENT}" -c "${NEXTCLOUD_CONTAINER}" -- \
  cat /var/www/html/config/config.php >"${OUTPUT_DIR}/nextcloud/config.php"
printf 'captured=%s\n' "${OUTPUT_DIR}/nextcloud/config.php"

section "database dump"
primary_pod="$(kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get cluster "${CNPG_CLUSTER}" -o jsonpath='{.status.currentPrimary}')"
pg_user="$(kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get secret "${CNPG_APP_SECRET}" -o jsonpath='{.data.user}' | base64 -d)"
pg_database="$(kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get secret "${CNPG_APP_SECRET}" -o jsonpath='{.data.dbname}' | base64 -d)"
pg_password="$(kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get secret "${CNPG_APP_SECRET}" -o jsonpath='{.data.password}' | base64 -d)"

kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" exec "${primary_pod}" -c postgres -- \
  env PGPASSWORD="${pg_password}" pg_dump \
    -h 127.0.0.1 \
    -U "${pg_user}" \
    -d "${pg_database}" \
    --format=custom \
    --no-owner >"${OUTPUT_DIR}/database/nextcloud-db.dump"
unset pg_password
printf 'captured=%s\n' "${OUTPUT_DIR}/database/nextcloud-db.dump"
printf 'database_dump_bytes=%s\n' "$(wc -c <"${OUTPUT_DIR}/database/nextcloud-db.dump")"

if [[ "${VERIFY_DB_DUMP}" == "true" ]]; then
  remote_dump="/controller/nextcloud-db-verify-$(date +%Y%m%d%H%M%S).dump"
  kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" cp \
    "${OUTPUT_DIR}/database/nextcloud-db.dump" \
    "${primary_pod}:${remote_dump}" \
    -c postgres
  kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" exec "${primary_pod}" -c postgres -- \
    pg_restore --list "${remote_dump}" >"${OUTPUT_DIR}/database/nextcloud-db.pg_restore.list"
  kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" exec "${primary_pod}" -c postgres -- \
    rm -f "${remote_dump}"
  printf 'verified_pg_restore_list=%s\n' "${OUTPUT_DIR}/database/nextcloud-db.pg_restore.list"
  awk '
    /^;     TOC Entries:/ { print "database_dump_toc_entries=" $4 }
    /^;     Format:/ { print "database_dump_format=" $3 }
  ' "${OUTPUT_DIR}/database/nextcloud-db.pg_restore.list"
else
  echo "verify_db_dump=false"
fi

section "kubernetes resources"
for resource in "${RESOURCE_NAMES[@]}"; do
  safe_name="${resource//\//_}"
  write_manifest "${resource}" "${OUTPUT_DIR}/kubernetes/resources/${safe_name}.yaml"
done

section "kubernetes secrets"
for secret in "${SECRET_NAMES[@]}"; do
  if kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get secret "${secret}" -o yaml >"${OUTPUT_DIR}/kubernetes/secrets/${secret}.yaml" 2>/dev/null; then
    printf 'captured_secret=%s key_count=' "${secret}"
    kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get secret "${secret}" -o json | jq '.data | length'
  else
    printf 'missing_secret=%s\n' "${secret}" | tee -a "${OUTPUT_DIR}/warnings.txt"
  fi
done

section "s3 inventory"
if [[ "${S3_INVENTORY_ENABLED}" == "true" ]]; then
  s3_bucket="$(kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get secret "${S3_SECRET}" -o jsonpath='{.data.S3_BUCKET}' | base64 -d)"
  s3_region="$(kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get secret "${S3_SECRET}" -o jsonpath='{.data.S3_REGION}' | base64 -d)"
  s3_access_key="$(kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get secret "${S3_SECRET}" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)"
  s3_secret_key="$(kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get secret "${S3_SECRET}" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)"

  AWS_ACCESS_KEY_ID="${s3_access_key}" \
  AWS_SECRET_ACCESS_KEY="${s3_secret_key}" \
  AWS_DEFAULT_REGION="${s3_region}" \
  aws s3api get-bucket-versioning --bucket "${s3_bucket}" >"${OUTPUT_DIR}/s3/bucket-versioning.json" 2>"${OUTPUT_DIR}/s3/bucket-versioning.stderr" || true

  AWS_ACCESS_KEY_ID="${s3_access_key}" \
  AWS_SECRET_ACCESS_KEY="${s3_secret_key}" \
  AWS_DEFAULT_REGION="${s3_region}" \
  aws s3 ls "s3://${s3_bucket}" --recursive --summarize >"${OUTPUT_DIR}/s3/bucket-inventory.txt"

  unset s3_access_key s3_secret_key
  printf 'captured=%s\n' "${OUTPUT_DIR}/s3/bucket-inventory.txt"
  awk '
    /Total Objects:/ { print "s3_total_objects=" $3 }
    /Total Size:/ { print "s3_total_bytes=" $3 }
  ' "${OUTPUT_DIR}/s3/bucket-inventory.txt"
else
  echo "s3_inventory_enabled=false"
fi

section "checksums"
(
  cd "${OUTPUT_DIR}"
  find . -type f -print0 | sort -z | xargs -0 shasum -a 256 > SHA256SUMS
)
printf 'captured=%s\n' "${OUTPUT_DIR}/SHA256SUMS"

section "restore set"
cat <<EOF | tee "${OUTPUT_DIR}/RESTORE_SET.txt"
This directory contains sensitive production restore material.

Captured:
- Nextcloud config.php, including the Nextcloud secret.
- CNPG custom-format database dump.
- Kubernetes resource snapshots.
- Kubernetes Secret YAML for the selected Nextcloud-related secrets.
- S3 bucket inventory/versioning metadata when enabled.
- SHA256SUMS for captured files.

Still required before production cutover:
- Confirm this dump can be restored into a disposable database.
- Confirm the S3 bucket is retained, versioned, provider-protected, or copied to a protected backup location.
- Capture a final backup again during maintenance mode immediately before cutover.

Do not commit this directory to Git.
EOF
