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

TARGET_NAMESPACE="${TARGET_NAMESPACE:-nextcloud}"
TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-nextcloud-migration-clean}"

OUTPUT_DIR="${OUTPUT_DIR:-/tmp/nextcloud-strategy-a-plan-$(date +%Y%m%d-%H%M%S)}"
APP_PATTERN="${APP_PATTERN:-files_versions|files_trashbin|files_sharing|encryption|photos|preview|memories|richdocuments|user_ldap|user_oidc|fulltext|external|calendar|contacts}"

mkdir -p "${OUTPUT_DIR}"

occ() {
  local namespace="$1"
  local deployment="$2"
  shift 2

  kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" exec "deploy/${deployment}" -c nextcloud -- php occ "$@"
}

source_db_query() {
  local sql="$1"
  local pod pg_user pg_database pg_password

  pod="$(kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get cluster "${SOURCE_CNPG_CLUSTER}" -o jsonpath='{.status.currentPrimary}')"
  pg_user="$(kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get secret "${SOURCE_DB_APP_SECRET}" -o jsonpath='{.data.user}' | base64 -d)"
  pg_database="$(kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get secret "${SOURCE_DB_APP_SECRET}" -o jsonpath='{.data.dbname}' | base64 -d)"
  pg_password="$(kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get secret "${SOURCE_DB_APP_SECRET}" -o jsonpath='{.data.password}' | base64 -d)"

  kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" exec "${pod}" -c postgres -- \
    env PGPASSWORD="${pg_password}" psql \
      -h 127.0.0.1 \
      -U "${pg_user}" \
      -d "${pg_database}" \
      -v ON_ERROR_STOP=1 \
      -q \
      -At \
      -c "${sql}"

  unset pg_password
}

objectstore_presence() {
  local namespace="$1"
  local deployment="$2"
  local tmp

  tmp="$(mktemp)"
  if occ "${namespace}" "${deployment}" config:system:get objectstore >"${tmp}" 2>/dev/null; then
    rm -f "${tmp}"
    echo "true"
  else
    rm -f "${tmp}"
    echo "false"
  fi
}

write_occ_json() {
  local output="$1"
  local namespace="$2"
  local deployment="$3"
  shift 3

  occ "${namespace}" "${deployment}" "$@" >"${output}"
}

write_occ_text() {
  local output="$1"
  local namespace="$2"
  local deployment="$3"
  shift 3

  occ "${namespace}" "${deployment}" "$@" >"${output}"
}

share_sql="$(cat <<'SQL'
SELECT coalesce(
  jsonb_agg(
    jsonb_build_object(
      'id', s.id,
      'share_type', s.share_type,
      'share_type_name',
        CASE s.share_type
          WHEN 0 THEN 'user'
          WHEN 1 THEN 'group'
          WHEN 3 THEN 'public_link'
          WHEN 6 THEN 'federated_cloud'
          WHEN 7 THEN 'circle'
          WHEN 10 THEN 'talk'
          ELSE 'other'
        END,
      'share_with', s.share_with,
      'uid_owner', s.uid_owner,
      'uid_initiator', s.uid_initiator,
      'item_type', s.item_type,
      'file_source', s.file_source,
      'file_target', s.file_target,
      'source_cache_path', fc.path,
      'permissions', s.permissions,
      'accepted', s.accepted,
      'expiration', s.expiration,
      'share_name', s.share_name,
      'has_password', s.password IS NOT NULL,
      'has_token', s.token IS NOT NULL,
      'hide_download', s.hide_download,
      'label', s.label,
      'has_note', nullif(s.note, '') IS NOT NULL,
      'has_attributes', s.attributes IS NOT NULL
    )
    ORDER BY s.id
  ),
  '[]'::jsonb
)::text
FROM oc_share s
LEFT JOIN oc_filecache fc ON fc.fileid = s.file_source;
SQL
)"

history_sql="$(cat <<'SQL'
SELECT jsonb_build_object(
  'oc_filecache', (SELECT count(*) FROM oc_filecache),
  'oc_files_versions', (SELECT count(*) FROM oc_files_versions),
  'oc_files_trash', (SELECT count(*) FROM oc_files_trash),
  'oc_share', (SELECT count(*) FROM oc_share),
  'oc_dav_shares', (SELECT count(*) FROM oc_dav_shares)
)::text;
SQL
)"

write_occ_json "${OUTPUT_DIR}/source-users.json" "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}" user:list --output=json
write_occ_json "${OUTPUT_DIR}/target-users.json" "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}" user:list --output=json
write_occ_json "${OUTPUT_DIR}/source-groups.json" "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}" group:list --output=json
write_occ_json "${OUTPUT_DIR}/target-groups.json" "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}" group:list --output=json
write_occ_json "${OUTPUT_DIR}/source-apps.json" "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}" app:list --output=json
write_occ_json "${OUTPUT_DIR}/target-apps.json" "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}" app:list --output=json
write_occ_text "${OUTPUT_DIR}/source-status.txt" "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}" status
write_occ_text "${OUTPUT_DIR}/target-status.txt" "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}" status
write_occ_text "${OUTPUT_DIR}/source-encryption-status.txt" "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}" encryption:status
write_occ_text "${OUTPUT_DIR}/target-encryption-status.txt" "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}" encryption:status
source_db_query "${share_sql}" | jq . >"${OUTPUT_DIR}/source-shares.json"
source_db_query "${history_sql}" | jq . >"${OUTPUT_DIR}/source-metadata-counts.json"

source_objectstore_present="$(objectstore_presence "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}")"
target_objectstore_present="$(objectstore_presence "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}")"
generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -n \
  --arg generated_at "${generated_at}" \
  --arg context "${KUBE_CONTEXT}" \
  --arg source "${SOURCE_NAMESPACE}/${SOURCE_DEPLOYMENT}" \
  --arg target "${TARGET_NAMESPACE}/${TARGET_DEPLOYMENT}" \
  --arg source_objectstore_present "${source_objectstore_present}" \
  --arg target_objectstore_present "${target_objectstore_present}" \
  --argjson source_users "$(cat "${OUTPUT_DIR}/source-users.json")" \
  --argjson target_users "$(cat "${OUTPUT_DIR}/target-users.json")" \
  --argjson source_groups "$(cat "${OUTPUT_DIR}/source-groups.json")" \
  --argjson target_groups "$(cat "${OUTPUT_DIR}/target-groups.json")" \
  --argjson source_apps "$(cat "${OUTPUT_DIR}/source-apps.json")" \
  --argjson target_apps "$(cat "${OUTPUT_DIR}/target-apps.json")" \
  --argjson source_shares "$(cat "${OUTPUT_DIR}/source-shares.json")" \
  --argjson metadata_counts "$(cat "${OUTPUT_DIR}/source-metadata-counts.json")" \
  --arg app_pattern "${APP_PATTERN}" \
  '
  def sorted_keys: keys | sort;
  def app_names($apps): ($apps.enabled // {}) | keys | map(select(test($app_pattern))) | sort;
  def user_group_pairs($groups):
    [
      $groups
      | to_entries[]
      | .key as $group
      | (.value // [])[]
      | {group: $group, user: .}
    ];

  user_group_pairs($source_groups) as $source_pairs
  | user_group_pairs($target_groups) as $target_pairs
  | {
      generated_at: $generated_at,
      context: $context,
      source: $source,
      target: $target,
      safety_boundary: {
        dry_run_only: true,
        no_nextcloud_changes_made: true,
        no_raw_s3_copy: true,
        migration_method: "Strategy A: clean filesystem-backed target plus metadata-aware WebDAV/API copy"
      },
      storage_state: {
        source_objectstore_present: ($source_objectstore_present == "true"),
        target_objectstore_present: ($target_objectstore_present == "true")
      },
      users: {
        source_count: ($source_users | length),
        target_count: ($target_users | length),
        missing_on_target: (($source_users | sorted_keys) - ($target_users | sorted_keys)),
        extra_on_target: (($target_users | sorted_keys) - ($source_users | sorted_keys))
      },
      groups: {
        source_count: ($source_groups | length),
        target_count: ($target_groups | length),
        missing_on_target: (($source_groups | sorted_keys) - ($target_groups | sorted_keys)),
        extra_on_target: (($target_groups | sorted_keys) - ($source_groups | sorted_keys)),
        missing_memberships_on_target: ($source_pairs - $target_pairs)
      },
      apps_affecting_files: {
        source: app_names($source_apps),
        target: app_names($target_apps),
        source_only: (app_names($source_apps) - app_names($target_apps)),
        target_only: (app_names($target_apps) - app_names($source_apps))
      },
      shares: {
        source_total: ($source_shares | length),
        recreatable_user_or_group_count: ($source_shares | map(select(.share_type == 0 or .share_type == 1)) | length),
        manual_review_count: ($source_shares | map(select((.share_type == 0 or .share_type == 1) | not)) | length),
        with_password_count: ($source_shares | map(select(.has_password == true)) | length),
        with_expiration_count: ($source_shares | map(select(.expiration != null)) | length),
        with_note_or_attributes_count: ($source_shares | map(select(.has_note == true or .has_attributes == true)) | length),
        recreate_candidates: (
          $source_shares
          | map(select(.share_type == 0 or .share_type == 1))
          | map({
              id,
              share_type,
              share_type_name,
              uid_owner,
              share_with,
              file_target,
              source_cache_path,
              permissions,
              expiration,
              share_name,
              hide_download,
              label,
              has_note,
              has_attributes
            })
        ),
        manual_review: (
          $source_shares
          | map(select((.share_type == 0 or .share_type == 1) | not))
          | map({
              id,
              share_type,
              share_type_name,
              uid_owner,
              share_with,
              file_target,
              source_cache_path,
              permissions,
              expiration,
              share_name,
              has_password,
              has_token
            })
        )
      },
      metadata_boundary: {
        source_counts: $metadata_counts,
        plain_webdav_copy_preserves_current_visible_files: true,
        plain_webdav_copy_preserves_source_versions: false,
        plain_webdav_copy_preserves_source_trashbin: false,
        shares_require_api_recreation: true
      },
      recommended_sequence: [
        "confirm backups and maintenance-mode plan",
        "create or map users on the clean encrypted target",
        "create missing groups and memberships on the target",
        "copy current visible files through WebDAV or another metadata-aware path",
        "recreate in-scope user and group shares through the OCS Share API",
        "treat public/federated/special shares, versions, and trashbin as manual review unless a supported migration tool is selected",
        "validate file counts, checksums, shares, encryption headers, previews, search, and sync clients"
      ]
    }
  ' >"${OUTPUT_DIR}/strategy-a-plan.json"

jq -r '
  "strategy_a_plan=" + input_filename,
  "source_users=" + (.users.source_count | tostring),
  "target_users=" + (.users.target_count | tostring),
  "missing_target_users=" + (.users.missing_on_target | length | tostring),
  "source_groups=" + (.groups.source_count | tostring),
  "target_groups=" + (.groups.target_count | tostring),
  "missing_target_groups=" + (.groups.missing_on_target | length | tostring),
  "missing_target_group_memberships=" + (.groups.missing_memberships_on_target | length | tostring),
  "source_shares=" + (.shares.source_total | tostring),
  "recreatable_user_or_group_shares=" + (.shares.recreatable_user_or_group_count | tostring),
  "manual_review_shares=" + (.shares.manual_review_count | tostring),
  "source_versions_rows=" + (.metadata_boundary.source_counts.oc_files_versions | tostring),
  "source_trash_rows=" + (.metadata_boundary.source_counts.oc_files_trash | tostring),
  "target_objectstore_present=" + (.storage_state.target_objectstore_present | tostring),
  "dry_run_only=" + (.safety_boundary.dry_run_only | tostring)
' "${OUTPUT_DIR}/strategy-a-plan.json"

cat <<EOF

Wrote Strategy A planning artifacts to:
${OUTPUT_DIR}

Review ${OUTPUT_DIR}/strategy-a-plan.json before building or running any bulk migration tooling.
This script does not copy files, create users, recreate shares, change config, or touch the S3 bucket.
EOF
