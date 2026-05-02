#!/usr/bin/env bash
set -euo pipefail

if [[ -f "${HOME}/.bash_profile" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.bash_profile" >/dev/null 2>&1
fi

KUBE_CONTEXT="${KUBE_CONTEXT:-admin@prod}"
SOURCE_SERVICE_URL="${SOURCE_SERVICE_URL:-http://nextcloud.default.svc.cluster.local}"
TARGET_SERVICE_URL="${TARGET_SERVICE_URL:-http://127.0.0.1}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-nextcloud}"
TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-nextcloud-migration-clean}"

SOURCE_PASSWORD_FILE="${SOURCE_PASSWORD_FILE:-}"
TARGET_PASSWORD_FILE="${TARGET_PASSWORD_FILE:-}"
USER_LIST_FILE="${USER_LIST_FILE:-}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/nextcloud-webdav-copy-users-$(date +%Y%m%d-%H%M%S)}"

COPY_ROOT="${COPY_ROOT:-}"
ALLOW_ENTIRE_HOME="${ALLOW_ENTIRE_HOME:-true}"
APPLY="${APPLY:-false}"
MAX_FILES="${MAX_FILES:-1000000}"
VERIFY_AFTER_COPY="${VERIFY_AFTER_COPY:-true}"
VERIFY_RAW_ENCRYPTION="${VERIFY_RAW_ENCRYPTION:-true}"
SKIP_MISSING_TARGET_PASSWORD="${SKIP_MISSING_TARGET_PASSWORD:-false}"

TARGET_ADMIN_USER="${TARGET_ADMIN_USER:-admin}"
TARGET_ADMIN_SECRET_NAME="${TARGET_ADMIN_SECRET_NAME:-nextcloud-migration-secret}"
TARGET_ADMIN_SECRET_KEY="${TARGET_ADMIN_SECRET_KEY:-NEXTCLOUD_ADMIN_PASSWORD}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${SOURCE_PASSWORD_FILE}" || ! -f "${SOURCE_PASSWORD_FILE}" ]]; then
  echo "SOURCE_PASSWORD_FILE is required and must point to source-app-passwords.tsv" >&2
  exit 2
fi

if [[ -z "${TARGET_PASSWORD_FILE}" || ! -f "${TARGET_PASSWORD_FILE}" ]]; then
  echo "TARGET_PASSWORD_FILE is required and must point to target-user-passwords.tsv" >&2
  exit 2
fi

mkdir -p "${OUTPUT_DIR}"
chmod 700 "${OUTPUT_DIR}"

decode_base64() {
  if base64 --decode >/dev/null 2>&1 </dev/null; then
    base64 --decode
  else
    base64 -D
  fi
}

lookup_tsv_password() {
  local file="$1"
  local user="$2"
  awk -F '\t' -v user="${user}" 'NR > 1 && $1 == user { print $2; found = 1; exit } END { if (!found) exit 1 }' "${file}"
}

target_admin_password() {
  local encoded
  encoded="$(kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" get secret "${TARGET_ADMIN_SECRET_NAME}" -o json | \
    jq -r --arg key "${TARGET_ADMIN_SECRET_KEY}" '.data[$key] // empty')"
  if [[ -z "${encoded}" ]]; then
    return 1
  fi
  printf '%s' "${encoded}" | decode_base64
}

users_file="${OUTPUT_DIR}/users.txt"
if [[ -n "${USER_LIST_FILE}" ]]; then
  cp "${USER_LIST_FILE}" "${users_file}"
else
  awk -F '\t' 'NR > 1 { print $1 }' "${SOURCE_PASSWORD_FILE}" | sort >"${users_file}"
fi

summary_file="${OUTPUT_DIR}/copy-users-summary.tsv"
printf 'user\tstatus\treport\n' >"${summary_file}"

while IFS= read -r user; do
  [[ -z "${user}" ]] && continue

  source_password="$(lookup_tsv_password "${SOURCE_PASSWORD_FILE}" "${user}")"
  target_password=""
  if target_password="$(lookup_tsv_password "${TARGET_PASSWORD_FILE}" "${user}" 2>/dev/null)"; then
    :
  elif [[ "${user}" == "${TARGET_ADMIN_USER}" ]] && target_password="$(target_admin_password)"; then
    :
  elif [[ "${SKIP_MISSING_TARGET_PASSWORD}" == "true" ]]; then
    printf '%s\tskipped_missing_target_password\t\n' "${user}" | tee -a "${summary_file}"
    continue
  else
    echo "missing_target_password user=${user}" >&2
    exit 1
  fi

  user_output_dir="${OUTPUT_DIR}/users/${user}"
  mkdir -p "${user_output_dir}"
  chmod 700 "${user_output_dir}"

  SOURCE_SERVICE_URL="${SOURCE_SERVICE_URL}" \
  TARGET_SERVICE_URL="${TARGET_SERVICE_URL}" \
  KUBE_CONTEXT="${KUBE_CONTEXT}" \
  TARGET_NAMESPACE="${TARGET_NAMESPACE}" \
  TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT}" \
  SOURCE_USER="${user}" \
  TARGET_USER="${user}" \
  SOURCE_PASSWORD="${source_password}" \
  TARGET_PASSWORD="${target_password}" \
  COPY_ROOT="${COPY_ROOT}" \
  ALLOW_ENTIRE_HOME="${ALLOW_ENTIRE_HOME}" \
  APPLY="${APPLY}" \
  MAX_FILES="${MAX_FILES}" \
  VERIFY_AFTER_COPY="${VERIFY_AFTER_COPY}" \
  VERIFY_RAW_ENCRYPTION="${VERIFY_RAW_ENCRYPTION}" \
  OUTPUT_DIR="${user_output_dir}" \
    "${script_dir}/nextcloud-webdav-copy-root.sh"

  report="${user_output_dir}/webdav-copy-root-report.json"
  printf '%s\tok\t%s\n' "${user}" "${report}" | tee -a "${summary_file}"
done <"${users_file}"

echo "copy_users_summary=${summary_file}"
echo "sensitive_input_files=true"
