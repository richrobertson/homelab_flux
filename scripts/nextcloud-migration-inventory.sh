#!/usr/bin/env bash
set -euo pipefail

if [[ -f "${HOME}/.bash_profile" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.bash_profile" >/dev/null 2>&1
fi

KUBE_CONTEXT="${KUBE_CONTEXT:-admin@staging}"

SOURCE_NAMESPACE="${SOURCE_NAMESPACE:-default}"
SOURCE_DEPLOYMENT="${SOURCE_DEPLOYMENT:-nextcloud}"
SOURCE_CNPG_CLUSTER="${SOURCE_CNPG_CLUSTER:-nextcloud-cnpg}"
SOURCE_DB_APP_SECRET="${SOURCE_DB_APP_SECRET:-nextcloud-cnpg-app}"
SOURCE_S3_CONFIGMAP="${SOURCE_S3_CONFIGMAP:-nextcloud-s3-staging}"
SOURCE_S3_SECRET="${SOURCE_S3_SECRET:-nextcloud-s3-staging}"

TARGET_NAMESPACE="${TARGET_NAMESPACE:-nextcloud}"
TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-nextcloud-migration-clean}"
TARGET_CNPG_CLUSTER="${TARGET_CNPG_CLUSTER:-nextcloud-migration-clean-cnpg}"
TARGET_DB_APP_SECRET="${TARGET_DB_APP_SECRET:-nextcloud-migration-clean-cnpg-app}"

PRINT_IDENTIFIERS="${PRINT_IDENTIFIERS:-false}"
RUN_SOURCE_BUCKET_INVENTORY="${RUN_SOURCE_BUCKET_INVENTORY:-false}"
APP_PATTERN="${APP_PATTERN:-files_versions|files_trashbin|files_sharing|encryption|photos|preview|memories|richdocuments|user_ldap|user_oidc|fulltext|external|calendar|contacts}"

section() {
  printf '\n== %s ==\n' "$1"
}

occ() {
  local namespace="$1"
  local deployment="$2"
  shift 2

  kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" exec "deploy/${deployment}" -c nextcloud -- php occ "$@"
}

safe_occ_objectstore_presence() {
  local label="$1"
  local namespace="$2"
  local deployment="$3"
  local tmp

  tmp="$(mktemp)"
  if occ "${namespace}" "${deployment}" config:system:get objectstore >"${tmp}" 2>/dev/null; then
    printf '%s_objectstore_config_present=true\n' "${label}"
  else
    printf '%s_objectstore_config_present=false\n' "${label}"
  fi
  rm -f "${tmp}"
}

json_object_count() {
  jq -r 'if type == "object" then length else 0 end'
}

print_user_group_inventory() {
  local label="$1"
  local namespace="$2"
  local deployment="$3"
  local users_json groups_json

  users_json="$(occ "${namespace}" "${deployment}" user:list --output=json)"
  groups_json="$(occ "${namespace}" "${deployment}" group:list --output=json)"

  printf '%s_user_count=%s\n' "${label}" "$(printf '%s\n' "${users_json}" | json_object_count)"
  printf '%s_group_count=%s\n' "${label}" "$(printf '%s\n' "${groups_json}" | json_object_count)"

  if [[ "${PRINT_IDENTIFIERS}" == "true" ]]; then
    printf '%s_users=\n' "${label}"
    printf '%s\n' "${users_json}" | jq -r 'keys[]' | sort | sed 's/^/  - /'
    printf '%s_groups=\n' "${label}"
    printf '%s\n' "${groups_json}" | jq -r 'keys[]' | sort | sed 's/^/  - /'
  else
    printf '%s_identifiers_printed=false\n' "${label}"
  fi
}

print_file_app_inventory() {
  local label="$1"
  local namespace="$2"
  local deployment="$3"

  printf '%s_file_affecting_apps=\n' "${label}"
  occ "${namespace}" "${deployment}" app:list --output=json | \
    jq -r --arg pattern "${APP_PATTERN}" '
      .enabled
      | keys[]
      | select(test($pattern))
    ' | sort | sed 's/^/  - /'
}

print_db_counts() {
  local label="$1"
  local namespace="$2"
  local cluster="$3"
  local secret="$4"
  local pod pg_user pg_database pg_password sql

  pod="$(kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" get cluster "${cluster}" -o jsonpath='{.status.currentPrimary}')"
  pg_user="$(kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" get secret "${secret}" -o jsonpath='{.data.user}' | base64 -d)"
  pg_database="$(kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" get secret "${secret}" -o jsonpath='{.data.dbname}' | base64 -d)"
  pg_password="$(kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" get secret "${secret}" -o jsonpath='{.data.password}' | base64 -d)"

  sql="$(cat <<'SQL'
CREATE TEMP TABLE migration_inventory_counts(table_name text, row_count bigint);
DO $$
DECLARE
  table_name text;
  row_count bigint;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'oc_accounts',
    'oc_dav_shares',
    'oc_filecache',
    'oc_files_metadata',
    'oc_files_trash',
    'oc_files_versions',
    'oc_group_admin',
    'oc_group_user',
    'oc_groups',
    'oc_mounts',
    'oc_share',
    'oc_share_external',
    'oc_storages',
    'oc_users'
  ]
  LOOP
    IF to_regclass('public.' || table_name) IS NULL THEN
      INSERT INTO migration_inventory_counts VALUES (table_name, NULL);
    ELSE
      EXECUTE format('SELECT count(*) FROM %I', table_name) INTO row_count;
      INSERT INTO migration_inventory_counts VALUES (table_name, row_count);
    END IF;
  END LOOP;
END $$;
SELECT table_name || '=' || coalesce(row_count::text, 'missing')
FROM migration_inventory_counts
ORDER BY table_name;
SQL
)"

  printf '%s_database_counts=\n' "${label}"
  kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" exec "${pod}" -c postgres -- \
    env PGPASSWORD="${pg_password}" psql \
      -h 127.0.0.1 \
      -U "${pg_user}" \
      -d "${pg_database}" \
      -v ON_ERROR_STOP=1 \
      -q \
      -At \
      -c "${sql}" | sed 's/^/  /'

  unset pg_password
}

print_cluster_state() {
  local label="$1"
  local namespace="$2"
  local deployment="$3"
  local cluster="$4"
  local secret="$5"

  printf '%s_workload=' "${label}"
  kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" get deploy "${deployment}" \
    -o jsonpath='{.status.readyReplicas}/{.status.replicas} ready{"\n"}'
  printf '%s_database=' "${label}"
  kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" get cluster "${cluster}" \
    -o jsonpath='{.status.phase}{" primary="}{.status.currentPrimary}{"\n"}'
  printf '%s_database_secret_keys=\n' "${label}"
  kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" get secret "${secret}" -o json | \
    jq -r '.data | keys[]' | sort | sed 's/^/  - /'
}

print_storage_inventory() {
  local label="$1"
  local namespace="$2"
  local deployment="$3"

  printf '%s_storage_summary=\n' "${label}"
  if [[ "${PRINT_IDENTIFIERS}" == "true" ]]; then
    occ "${namespace}" "${deployment}" info:storages --output=json 2>/dev/null | \
      jq -r '.[] | "- id=\(.id) files=\(.files) available=\(.available)"' | sed 's/^/  /' || \
      printf '  info:storages unavailable\n'
    return
  fi

  occ "${namespace}" "${deployment}" info:storages --output=json 2>/dev/null | \
    jq -r '
      def kind:
        if (.id | startswith("object::store:")) then "objectstore_bucket"
        elif (.id | startswith("object::user:")) then "objectstore_user"
        elif (.id | startswith("home::")) then "filesystem_home"
        elif (.id | startswith("local::")) then "filesystem_local"
        else "other"
        end;

      {
        total_storages: length,
        total_files: (map(.files | tonumber) | add // 0),
        by_kind: (
          group_by(kind)
          | map({
              kind: (.[0] | kind),
              storages: length,
              files: (map(.files | tonumber) | add // 0)
            })
        )
      }
      | "total_storages=\(.total_storages)",
        "total_files=\(.total_files)",
        (.by_kind[] | "kind=\(.kind) storages=\(.storages) files=\(.files)"),
        "storage_identifiers_printed=false"
    ' | sed 's/^/  /' || printf '  info:storages unavailable\n'
}

print_bucket_inventory() {
  local bucket host port endpoint scheme

  bucket="$(kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get configmap "${SOURCE_S3_CONFIGMAP}" -o jsonpath='{.data.BUCKET_NAME}')"
  host="$(kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get configmap "${SOURCE_S3_CONFIGMAP}" -o jsonpath='{.data.BUCKET_HOST}')"
  port="$(kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get configmap "${SOURCE_S3_CONFIGMAP}" -o jsonpath='{.data.BUCKET_PORT}')"
  scheme="${SOURCE_BUCKET_SCHEME:-http}"
  endpoint="${scheme}://${host}"
  if [[ -n "${port}" ]]; then
    endpoint="${endpoint}:${port}"
  fi

  printf 'source_bucket_inventory_enabled=true\n'
  printf 'source_bucket_name=%s\n' "${bucket}"
  printf 'source_bucket_endpoint=%s\n' "${endpoint}"
  aws --endpoint-url "${endpoint}" s3 ls "s3://${bucket}" --recursive --summarize | \
    awk '
      /Total Objects:/ { print "source_bucket_object_count=" $3 }
      /Total Size:/ { print "source_bucket_total_bytes=" $3 }
    '
}

echo "Nextcloud S3-primary to encrypted filesystem target inventory"
echo "context=${KUBE_CONTEXT}"
echo "source=${SOURCE_NAMESPACE}/${SOURCE_DEPLOYMENT}"
echo "target=${TARGET_NAMESPACE}/${TARGET_DEPLOYMENT}"
echo "printed_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "warning=raw_s3_object_copy_is_not_a_nextcloud_migration"

section "source cluster state"
print_cluster_state "source" "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}" "${SOURCE_CNPG_CLUSTER}" "${SOURCE_DB_APP_SECRET}"

section "source objectstore inventory"
printf 'source_s3_configmap=%s/%s\n' "${SOURCE_NAMESPACE}" "${SOURCE_S3_CONFIGMAP}"
kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get configmap "${SOURCE_S3_CONFIGMAP}" -o json | \
  jq -r '.data | to_entries[] | select(.key | test("SECRET|KEY|PASSWORD|TOKEN") | not) | "\(.key)=\(.value)"' | sort
printf 'source_s3_secret_keys=\n'
kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get secret "${SOURCE_S3_SECRET}" -o json | \
  jq -r '.data | keys[]' | sort | sed 's/^/  - /'
safe_occ_objectstore_presence "source" "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}"

if [[ "${RUN_SOURCE_BUCKET_INVENTORY}" == "true" ]]; then
  print_bucket_inventory
else
  echo "source_bucket_inventory_enabled=false"
  echo "source_bucket_inventory_note=set RUN_SOURCE_BUCKET_INVENTORY=true to query object count and total bytes with aws cli"
fi

section "source nextcloud inventory"
occ "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}" status
occ "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}" encryption:status || true
print_file_app_inventory "source" "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}"
print_user_group_inventory "source" "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}"
print_db_counts "source" "${SOURCE_NAMESPACE}" "${SOURCE_CNPG_CLUSTER}" "${SOURCE_DB_APP_SECRET}"
print_storage_inventory "source" "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}"

section "target cluster state"
print_cluster_state "target" "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}" "${TARGET_CNPG_CLUSTER}" "${TARGET_DB_APP_SECRET}"

section "target nextcloud inventory"
occ "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}" status
occ "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}" encryption:status
safe_occ_objectstore_presence "target" "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}"
print_file_app_inventory "target" "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}"
print_user_group_inventory "target" "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}"
print_db_counts "target" "${TARGET_NAMESPACE}" "${TARGET_CNPG_CLUSTER}" "${TARGET_DB_APP_SECRET}"
print_storage_inventory "target" "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}"

section "target encrypted restore set"
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nextcloud-encryption-restore-set-inventory.sh"

section "operator notes"
cat <<'EOF'
- This inventory intentionally prints Secret key names only, not Secret values.
- Keep database dumps, config.php, app secrets, encryption key material, and encrypted NFS data together as one restore set.
- Do not use aws s3 sync or raw bucket object names as the filesystem migration path.
- Use WebDAV/API or a tested database-aware migration tool so Nextcloud metadata stays authoritative.
EOF
