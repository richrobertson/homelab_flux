#!/usr/bin/env bash
set -euo pipefail

if [[ -f "${HOME}/.bash_profile" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.bash_profile" >/dev/null 2>&1
fi

KUBE_CONTEXT="${KUBE_CONTEXT:-admin@prod}"
SOURCE_NAMESPACE="${SOURCE_NAMESPACE:-default}"
SOURCE_DEPLOYMENT="${SOURCE_DEPLOYMENT:-nextcloud}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-nextcloud}"
TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-nextcloud-migration-clean}"
APPLY="${APPLY:-false}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/nextcloud-user-group-reconcile-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "${OUTPUT_DIR}"
chmod 700 "${OUTPUT_DIR}"

occ() {
  local namespace="$1"
  local deployment="$2"
  shift 2

  kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" exec "deploy/${deployment}" -c nextcloud -- php occ "$@"
}

source_users_json="$(occ "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}" user:list --output=json)"
target_users_json="$(occ "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}" user:list --output=json)"
source_groups_json="$(occ "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}" group:list --output=json)"
target_groups_json="$(occ "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}" group:list --output=json)"

plan_file="${OUTPUT_DIR}/user-group-reconcile-plan.json"
password_file="${OUTPUT_DIR}/target-user-passwords.tsv"

jq -n \
  --arg context "${KUBE_CONTEXT}" \
  --arg source "${SOURCE_NAMESPACE}/${SOURCE_DEPLOYMENT}" \
  --arg target "${TARGET_NAMESPACE}/${TARGET_DEPLOYMENT}" \
  --arg apply "${APPLY}" \
  --argjson source_users "${source_users_json}" \
  --argjson target_users "${target_users_json}" \
  --argjson source_groups "${source_groups_json}" \
  --argjson target_groups "${target_groups_json}" \
  '
  def sorted_keys: keys | sort;
  def memberships($groups):
    [
      $groups
      | to_entries[]
      | .key as $group
      | (.value // [])[]
      | {group: $group, user: .}
    ];

  memberships($source_groups) as $source_memberships
  | memberships($target_groups) as $target_memberships
  | {
      generated_at: now | todateiso8601,
      context: $context,
      source: $source,
      target: $target,
      safety_boundary: {
        apply: ($apply == "true"),
        target_only: true,
        dry_run_by_default: true,
        does_not_touch_source: true,
        does_not_copy_files: true,
        does_not_change_objectstore_config: true
      },
      users: {
        source_count: ($source_users | length),
        target_count: ($target_users | length),
        missing_on_target: (($source_users | sorted_keys) - ($target_users | sorted_keys)),
        already_on_target: (($source_users | sorted_keys) - (($source_users | sorted_keys) - ($target_users | sorted_keys)))
      },
      groups: {
        source_count: ($source_groups | length),
        target_count: ($target_groups | length),
        missing_on_target: (($source_groups | sorted_keys) - ($target_groups | sorted_keys)),
        missing_memberships_on_target: ($source_memberships - $target_memberships)
      }
    }
  ' >"${plan_file}"

printf 'plan=%s\n' "${plan_file}"
jq -r '
  "apply=" + (.safety_boundary.apply | tostring),
  "source_users=" + (.users.source_count | tostring),
  "target_users=" + (.users.target_count | tostring),
  "missing_target_users=" + (.users.missing_on_target | length | tostring),
  "missing_target_groups=" + (.groups.missing_on_target | length | tostring),
  "missing_target_memberships=" + (.groups.missing_memberships_on_target | length | tostring)
' "${plan_file}"

if [[ "${APPLY}" != "true" ]]; then
  echo "dry_run_only=true"
  echo "Set APPLY=true to create missing target users, groups, and memberships."
  exit 0
fi

printf 'user\tpassword\n' >"${password_file}"
chmod 600 "${password_file}"

while IFS= read -r user; do
  password="$(openssl rand -base64 36 | tr -d '\n')"
  kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" exec "deploy/${TARGET_DEPLOYMENT}" -c nextcloud -- \
    env OC_PASS="${password}" php occ user:add \
      --password-from-env \
      --display-name "${user}" \
      "${user}" >/dev/null
  printf '%s\t%s\n' "${user}" "${password}" >>"${password_file}"
  printf 'created_user=%s\n' "${user}"
done < <(jq -r '.users.missing_on_target[]' "${plan_file}")

while IFS= read -r group; do
  occ "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}" group:add "${group}" >/dev/null 2>&1 || true
  printf 'ensured_group=%s\n' "${group}"
done < <(jq -r '.groups.missing_on_target[]' "${plan_file}")

jq -r '.groups.missing_memberships_on_target[] | @base64' "${plan_file}" | while IFS= read -r encoded; do
  membership="$(printf '%s' "${encoded}" | base64 -d)"
  group="$(printf '%s' "${membership}" | jq -r '.group')"
  user="$(printf '%s' "${membership}" | jq -r '.user')"
  occ "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}" group:adduser "${group}" "${user}" >/dev/null 2>&1 || true
  printf 'ensured_membership=%s/%s\n' "${group}" "${user}"
done

echo "password_file=${password_file}"
echo "sensitive_output=true"
echo "Do not commit the password file. Use it only for controlled WebDAV import credentials."
