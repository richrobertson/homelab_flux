#!/usr/bin/env bash
set -euo pipefail

if [[ -f "${HOME}/.bash_profile" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.bash_profile" >/dev/null 2>&1
fi

KUBE_CONTEXT="${KUBE_CONTEXT:-admin@prod}"
SOURCE_NAMESPACE="${SOURCE_NAMESPACE:-default}"
SOURCE_CNPG_CLUSTER="${SOURCE_CNPG_CLUSTER:-nextcloud-cnpg}"
SOURCE_DB_APP_SECRET="${SOURCE_DB_APP_SECRET:-nextcloud-cnpg-app}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/nextcloud-file-state-boundary-report-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "${OUTPUT_DIR}"
chmod 700 "${OUTPUT_DIR}"

pod="$(kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get cluster "${SOURCE_CNPG_CLUSTER}" -o jsonpath='{.status.currentPrimary}')"
pg_user="$(kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get secret "${SOURCE_DB_APP_SECRET}" -o jsonpath='{.data.user}' | base64 -d)"
pg_database="$(kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get secret "${SOURCE_DB_APP_SECRET}" -o jsonpath='{.data.dbname}' | base64 -d)"
pg_password="$(kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get secret "${SOURCE_DB_APP_SECRET}" -o jsonpath='{.data.password}' | base64 -d)"

report_file="${OUTPUT_DIR}/file-state-boundary-report.json"

sql_quote() {
  printf '%s' "$1" | sed "s/'/''/g"
}

sql_source_namespace="$(sql_quote "${SOURCE_NAMESPACE}")"
sql_source_cnpg_cluster="$(sql_quote "${SOURCE_CNPG_CLUSTER}")"

sql="$(cat <<'SQL'
WITH source_rows AS (
  SELECT
    regexp_replace(s.id, '^object::user:', '') AS user_id,
    CASE
      WHEN f.path = '' THEN 'storage_root'
      ELSE regexp_replace(f.path, '/.*$', '')
    END AS top_path,
    COALESCE(m.mimetype, 'unknown') AS mimetype,
    greatest(f.size, 0) AS size
  FROM oc_storages s
  JOIN oc_filecache f ON f.storage = s.numeric_id
  LEFT JOIN oc_mimetypes m ON m.id = f.mimetype
  WHERE s.id LIKE 'object::user:%'
),
grouped AS (
  SELECT
    user_id,
    top_path,
    count(*) FILTER (WHERE mimetype = 'httpd/unix-directory') AS directories,
    count(*) FILTER (WHERE mimetype <> 'httpd/unix-directory') AS files,
    COALESCE(sum(size) FILTER (WHERE mimetype <> 'httpd/unix-directory'), 0)::bigint AS file_bytes
  FROM source_rows
  GROUP BY user_id, top_path
),
trash AS (
  SELECT count(*) AS rows FROM oc_files_trash
),
versions AS (
  SELECT count(*) AS rows FROM oc_files_versions
)
SELECT jsonb_pretty(jsonb_build_object(
  'generated_at', now(),
  'source_namespace', '__SOURCE_NAMESPACE__',
  'source_cnpg_cluster', '__SOURCE_CNPG_CLUSTER__',
  'summary', (
    SELECT jsonb_object_agg(
      top_path,
      jsonb_build_object(
        'directories', directories,
        'files', files,
        'file_bytes', file_bytes
      )
      ORDER BY top_path
    )
    FROM (
      SELECT
        top_path,
        sum(directories)::bigint AS directories,
        sum(files)::bigint AS files,
        sum(file_bytes)::bigint AS file_bytes
      FROM grouped
      GROUP BY top_path
    ) totals
  ),
  'by_user', (
    SELECT jsonb_object_agg(
      user_id,
      states
      ORDER BY user_id
    )
    FROM (
      SELECT
        user_id,
        jsonb_object_agg(
          top_path,
          jsonb_build_object(
            'directories', directories,
            'files', files,
            'file_bytes', file_bytes
          )
          ORDER BY top_path
        ) AS states
      FROM grouped
      GROUP BY user_id
    ) users
  ),
  'database_rows', jsonb_build_object(
    'oc_files_trash', (SELECT rows FROM trash),
    'oc_files_versions', (SELECT rows FROM versions)
  ),
  'strategy_a_plain_webdav_boundary', jsonb_build_object(
    'copies_current_visible_files_under_files', true,
    'preserves_trashbin_state', false,
    'preserves_versions_state', false
  )
));
SQL
)"
sql="${sql/__SOURCE_NAMESPACE__/${sql_source_namespace}}"
sql="${sql/__SOURCE_CNPG_CLUSTER__/${sql_source_cnpg_cluster}}"

kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" exec "${pod}" -c postgres -- \
  env PGPASSWORD="${pg_password}" psql \
    -h 127.0.0.1 \
    -U "${pg_user}" \
    -d "${pg_database}" \
    -v ON_ERROR_STOP=1 \
    -q \
    -At \
    -c "${sql}" >"${report_file}"

unset pg_password

jq -r '
  "file_state_boundary_report=" + input_filename,
  "current_visible_files=" + ((.summary.files.files // 0) | tostring),
  "current_visible_file_bytes=" + ((.summary.files.file_bytes // 0) | tostring),
  "trashbin_files=" + ((.summary.files_trashbin.files // 0) | tostring),
  "trashbin_file_bytes=" + ((.summary.files_trashbin.file_bytes // 0) | tostring),
  "versions_files=" + ((.summary.files_versions.files // 0) | tostring),
  "versions_file_bytes=" + ((.summary.files_versions.file_bytes // 0) | tostring),
  "oc_files_trash_rows=" + (.database_rows.oc_files_trash | tostring),
  "oc_files_versions_rows=" + (.database_rows.oc_files_versions | tostring),
  "plain_webdav_preserves_trashbin_state=" + (.strategy_a_plain_webdav_boundary.preserves_trashbin_state | tostring),
  "plain_webdav_preserves_versions_state=" + (.strategy_a_plain_webdav_boundary.preserves_versions_state | tostring)
' "${report_file}"

cat <<EOF

Wrote file-state boundary report to:
${report_file}

This report prints aggregate counts and bytes only. It intentionally does not
print file names or secret values.
EOF
