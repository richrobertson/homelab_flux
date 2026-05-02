#!/usr/bin/env bash
set -euo pipefail

if [[ -f "${HOME}/.bash_profile" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.bash_profile" >/dev/null 2>&1
fi

KUBE_CONTEXT="${KUBE_CONTEXT:-admin@staging}"
SOURCE_NAMESPACE="${SOURCE_NAMESPACE:-default}"
SOURCE_DEPLOYMENT="${SOURCE_DEPLOYMENT:-nextcloud}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-nextcloud}"
TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-nextcloud-migration-clean}"
SOURCE_SERVICE_URL="${SOURCE_SERVICE_URL:-http://nextcloud.default.svc.cluster.local}"
TARGET_SERVICE_URL="${TARGET_SERVICE_URL:-http://127.0.0.1}"
SMOKE_OWNER="${SMOKE_OWNER:-migration-share-owner}"
SMOKE_RECIPIENT="${SMOKE_RECIPIENT:-migration-share-recipient}"
SMOKE_GROUP="${SMOKE_GROUP:-migration-share-dryrun}"

password="$(openssl rand -base64 36 | tr -d '\n')"
run_id="$(date +%Y%m%d-%H%M%S)"

occ() {
  local namespace="$1"
  local deployment="$2"
  shift 2
  kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" exec "deploy/${deployment}" -c nextcloud -- php occ "$@"
}

ensure_user() {
  local namespace="$1"
  local deployment="$2"
  local user="$3"

  if occ "${namespace}" "${deployment}" user:info "${user}" >/dev/null 2>&1; then
    kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" exec "deploy/${deployment}" -c nextcloud -- \
      env OC_PASS="${password}" php occ user:resetpassword --password-from-env "${user}" >/dev/null
  else
    kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" exec "deploy/${deployment}" -c nextcloud -- \
      env OC_PASS="${password}" php occ user:add --password-from-env \
      --display-name "${user}" \
      --group "${SMOKE_GROUP}" \
      "${user}" >/dev/null
  fi

  occ "${namespace}" "${deployment}" group:adduser "${SMOKE_GROUP}" "${user}" >/dev/null 2>&1 || true
}

for ns_deploy in "${SOURCE_NAMESPACE} ${SOURCE_DEPLOYMENT}" "${TARGET_NAMESPACE} ${TARGET_DEPLOYMENT}"; do
  namespace="${ns_deploy%% *}"
  deployment="${ns_deploy#* }"
  occ "${namespace}" "${deployment}" group:add "${SMOKE_GROUP}" >/dev/null 2>&1 || true
  ensure_user "${namespace}" "${deployment}" "${SMOKE_OWNER}"
  ensure_user "${namespace}" "${deployment}" "${SMOKE_RECIPIENT}"
done

kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" exec -i "deploy/${TARGET_DEPLOYMENT}" -c nextcloud -- \
  env \
    SMOKE_OWNER="${SMOKE_OWNER}" \
    SMOKE_RECIPIENT="${SMOKE_RECIPIENT}" \
    SMOKE_PASS="${password}" \
    SMOKE_RUN_ID="${run_id}" \
    SOURCE_SERVICE_URL="${SOURCE_SERVICE_URL}" \
    TARGET_SERVICE_URL="${TARGET_SERVICE_URL}" \
    sh -s <<'REMOTE'
set -eu

folder="migration-share-dryrun-${SMOKE_RUN_ID}"
file="shared-${SMOKE_RUN_ID}.txt"
payload="Nextcloud share metadata dry run ${SMOKE_RUN_ID}\nowner=${SMOKE_OWNER}\nrecipient=${SMOKE_RECIPIENT}\n"

source_dav="${SOURCE_SERVICE_URL}/remote.php/dav/files/${SMOKE_OWNER}"
target_dav="${TARGET_SERVICE_URL}/remote.php/dav/files/${SMOKE_OWNER}"
target_recipient_dav="${TARGET_SERVICE_URL}/remote.php/dav/files/${SMOKE_RECIPIENT}"
source_ocs="${SOURCE_SERVICE_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares"
target_ocs="${TARGET_SERVICE_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares"

ocs_ok() {
  php -r '
    $json = json_decode(stream_get_contents(STDIN), true);
    $code = $json["ocs"]["meta"]["statuscode"] ?? null;
    if (!in_array($code, [100, 200], true)) {
      fwrite(STDERR, "ocs_not_ok statuscode=" . var_export($code, true) . "\n");
      exit(1);
    }
  '
}

mkcol() {
  curl -fsS -u "${SMOKE_OWNER}:${SMOKE_PASS}" -X MKCOL "$1" >/dev/null || true
}

upload() {
  printf '%b' "${payload}" | curl -fsS -u "${SMOKE_OWNER}:${SMOKE_PASS}" -T - "$1" >/dev/null
}

share_file() {
  local ocs_url="$1"
  local path="$2"
  curl -fsS -u "${SMOKE_OWNER}:${SMOKE_PASS}" \
    -H 'OCS-APIRequest: true' \
    -H 'Accept: application/json' \
    -d "path=${path}" \
    -d 'shareType=0' \
    -d "shareWith=${SMOKE_RECIPIENT}" \
    "${ocs_url}" | ocs_ok
}

mkcol "${source_dav}/${folder}"
upload "${source_dav}/${folder}/${file}"
share_file "${source_ocs}" "/${folder}/${file}"

mkcol "${target_dav}/${folder}"
curl -fsS -u "${SMOKE_OWNER}:${SMOKE_PASS}" "${source_dav}/${folder}/${file}" | \
  curl -fsS -u "${SMOKE_OWNER}:${SMOKE_PASS}" -T - "${target_dav}/${folder}/${file}" >/dev/null
share_file "${target_ocs}" "/${folder}/${file}"

owner_sha="$(curl -fsS -u "${SMOKE_OWNER}:${SMOKE_PASS}" "${target_dav}/${folder}/${file}" | sha256sum | awk '{print $1}')"
recipient_sha="$(curl -fsS -u "${SMOKE_RECIPIENT}:${SMOKE_PASS}" "${target_recipient_dav}/${file}" | sha256sum | awk '{print $1}')"

if [ "${owner_sha}" != "${recipient_sha}" ]; then
  echo "checksum_mismatch_after_share_recreate" >&2
  exit 1
fi

test -f "/var/www/html/data/${SMOKE_OWNER}/files/${folder}/${file}"
php occ files:scan "${SMOKE_OWNER}" --path="${SMOKE_OWNER}/files/${folder}" >/tmp/nextcloud-share-smoke-scan.txt
cat /tmp/nextcloud-share-smoke-scan.txt

printf 'share_recreate_ok owner=%s recipient=%s path=%s/%s sha256=%s\n' \
  "${SMOKE_OWNER}" "${SMOKE_RECIPIENT}" "${folder}" "${file}" "${owner_sha}"
REMOTE

unset password
