#!/usr/bin/env bash
set -euo pipefail

if [[ -f "${HOME}/.bash_profile" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.bash_profile" >/dev/null 2>&1
fi

KUBE_CONTEXT="${KUBE_CONTEXT:-admin@prod}"
SOURCE_NAMESPACE="${SOURCE_NAMESPACE:-default}"
SOURCE_DEPLOYMENT="${SOURCE_DEPLOYMENT:-nextcloud}"
MODE="${MODE:-create}"
TOKEN_NAME="${TOKEN_NAME:-nextcloud-s3-to-nfs-migration-$(date +%Y%m%d%H%M%S)}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/nextcloud-source-app-passwords-$(date +%Y%m%d-%H%M%S)}"
USER_LIST_FILE="${USER_LIST_FILE:-}"

mkdir -p "${OUTPUT_DIR}"
chmod 700 "${OUTPUT_DIR}"

occ() {
  kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" exec "deploy/${SOURCE_DEPLOYMENT}" -c nextcloud -- php occ "$@"
}

users_file="${OUTPUT_DIR}/users.txt"
password_file="${OUTPUT_DIR}/source-app-passwords.tsv"

if [[ -n "${USER_LIST_FILE}" ]]; then
  cp "${USER_LIST_FILE}" "${users_file}"
else
  occ user:list --output=json | jq -r 'keys[]' | sort >"${users_file}"
fi

case "${MODE}" in
  create)
    printf 'user\tapp_password\ttoken_name\n' >"${password_file}"
    chmod 600 "${password_file}"
    while IFS= read -r user; do
      tmp="$(mktemp)"
      occ user:auth-tokens:add --no-interaction --name "${TOKEN_NAME}" "${user}" >"${tmp}"
      app_password="$(awk '
        found == 1 && NF > 0 { print $0; exit }
        /^app password:/ { found = 1 }
      ' "${tmp}" | tr -d '\r')"
      rm -f "${tmp}"

      if [[ -z "${app_password}" ]]; then
        echo "failed_to_create_app_password user=${user}" >&2
        exit 1
      fi

      printf '%s\t%s\t%s\n' "${user}" "${app_password}" "${TOKEN_NAME}" >>"${password_file}"
      printf 'created_app_password user=%s token_name=%s\n' "${user}" "${TOKEN_NAME}"
    done <"${users_file}"
    echo "password_file=${password_file}"
    echo "sensitive_output=true"
    ;;

  delete)
    while IFS= read -r user; do
      token_ids="$(occ user:auth-tokens:list "${user}" --output=json | \
        jq -r --arg name "${TOKEN_NAME}" '.[] | select(.name == $name) | .id')"
      if [[ -z "${token_ids}" ]]; then
        printf 'no_matching_token user=%s token_name=%s\n' "${user}" "${TOKEN_NAME}"
        continue
      fi

      while IFS= read -r token_id; do
        [[ -z "${token_id}" ]] && continue
        occ user:auth-tokens:delete "${user}" "${token_id}" >/dev/null
        printf 'deleted_app_password user=%s token_id=%s token_name=%s\n' "${user}" "${token_id}" "${TOKEN_NAME}"
      done <<<"${token_ids}"
    done <"${users_file}"
    ;;

  *)
    echo "MODE must be create or delete" >&2
    exit 2
    ;;
esac
