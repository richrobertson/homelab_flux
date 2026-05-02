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
SMOKE_USER="${SMOKE_USER:-migration-history-dryrun}"
SMOKE_GROUP="${SMOKE_GROUP:-migration-history-dryrun}"
EXPECTED_MODULE="${EXPECTED_MODULE:-OC_DEFAULT_MODULE}"

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

  occ "${namespace}" "${deployment}" group:add "${SMOKE_GROUP}" >/dev/null 2>&1 || true

  if occ "${namespace}" "${deployment}" user:info "${SMOKE_USER}" >/dev/null 2>&1; then
    kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" exec "deploy/${deployment}" -c nextcloud -- \
      env OC_PASS="${password}" php occ user:resetpassword --password-from-env "${SMOKE_USER}" >/dev/null
  else
    kubectl --context "${KUBE_CONTEXT}" -n "${namespace}" exec "deploy/${deployment}" -c nextcloud -- \
      env OC_PASS="${password}" php occ user:add --password-from-env \
      --display-name "Migration History Dry Run" \
      --group "${SMOKE_GROUP}" \
      "${SMOKE_USER}" >/dev/null
  fi

  occ "${namespace}" "${deployment}" group:adduser "${SMOKE_GROUP}" "${SMOKE_USER}" >/dev/null 2>&1 || true
}

ensure_user "${SOURCE_NAMESPACE}" "${SOURCE_DEPLOYMENT}"
ensure_user "${TARGET_NAMESPACE}" "${TARGET_DEPLOYMENT}"

kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" exec -i "deploy/${TARGET_DEPLOYMENT}" -c nextcloud -- \
  env \
    SMOKE_USER="${SMOKE_USER}" \
    SMOKE_PASS="${password}" \
    SMOKE_RUN_ID="${run_id}" \
    SOURCE_SERVICE_URL="${SOURCE_SERVICE_URL}" \
    TARGET_SERVICE_URL="${TARGET_SERVICE_URL}" \
    EXPECTED_MODULE="${EXPECTED_MODULE}" \
    sh -s <<'REMOTE'
set -eu

root="migration-history-dryrun-${SMOKE_RUN_ID}"
versioned_file="versioned-${SMOKE_RUN_ID}.txt"
trash_file="trash-${SMOKE_RUN_ID}.txt"
source_dav="${SOURCE_SERVICE_URL}/remote.php/dav/files/${SMOKE_USER}"
target_dav="${TARGET_SERVICE_URL}/remote.php/dav/files/${SMOKE_USER}"
source_versions_dav="${SOURCE_SERVICE_URL}/remote.php/dav/versions/${SMOKE_USER}/versions"
target_versions_dav="${TARGET_SERVICE_URL}/remote.php/dav/versions/${SMOKE_USER}/versions"
source_trash_dav="${SOURCE_SERVICE_URL}/remote.php/dav/trashbin/${SMOKE_USER}/trash"
target_trash_dav="${TARGET_SERVICE_URL}/remote.php/dav/trashbin/${SMOKE_USER}/trash"

curl_user() {
  curl -fsS -u "${SMOKE_USER}:${SMOKE_PASS}" "$@"
}

hash_url() {
  curl_user "$1" | sha256sum | awk '{print $1}'
}

fileid_for() {
  local url="$1"
  curl_user -X PROPFIND -H 'Depth: 0' \
    --data '<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns"><d:prop><oc:fileid/></d:prop></d:propfind>' \
    "${url}" | sed -n 's#.*<oc:fileid>\([0-9][0-9]*\)</oc:fileid>.*#\1#p'
}

version_count_for() {
  local versions_base="$1"
  local fileid="$2"
  curl_user -X PROPFIND -H 'Depth: 1' "${versions_base}/${fileid}/" | \
    grep -o "/versions/${fileid}/[0-9][0-9]*" | wc -l | awk '{print $1}'
}

trash_count_for() {
  local trash_base="$1"
  local file="$2"
  curl_user -X PROPFIND -H 'Depth: 1' "${trash_base}" | \
    grep -o "${file}\\.d[0-9][0-9]*" | wc -l | awk '{print $1}'
}

curl_user -X MKCOL "${source_dav}/${root}" >/dev/null || true
curl_user -X MKCOL "${target_dav}/${root}" >/dev/null || true

printf 'version 1\nrun=%s\n' "${SMOKE_RUN_ID}" | curl_user -T - "${source_dav}/${root}/${versioned_file}" >/dev/null
sleep 1
printf 'version 2\nrun=%s\n' "${SMOKE_RUN_ID}" | curl_user -T - "${source_dav}/${root}/${versioned_file}" >/dev/null
sleep 1
printf 'version 3 final\nrun=%s\n' "${SMOKE_RUN_ID}" | curl_user -T - "${source_dav}/${root}/${versioned_file}" >/dev/null

printf 'trash me\nrun=%s\n' "${SMOKE_RUN_ID}" | curl_user -T - "${source_dav}/${root}/${trash_file}" >/dev/null
curl_user -X DELETE "${source_dav}/${root}/${trash_file}" >/dev/null

curl_user "${source_dav}/${root}/${versioned_file}" | curl_user -T - "${target_dav}/${root}/${versioned_file}" >/dev/null

source_sha="$(hash_url "${source_dav}/${root}/${versioned_file}")"
target_sha="$(hash_url "${target_dav}/${root}/${versioned_file}")"
if [ "${source_sha}" != "${target_sha}" ]; then
  echo "current_file_checksum_mismatch" >&2
  exit 1
fi

raw_path="/var/www/html/data/${SMOKE_USER}/files/${root}/${versioned_file}"
test -f "${raw_path}"
if ! head -c 96 "${raw_path}" | grep -q "HBEGIN:oc_encryption_module:${EXPECTED_MODULE}"; then
  echo "target_file_not_nextcloud_encrypted raw_path=${raw_path}" >&2
  exit 1
fi

source_fileid="$(fileid_for "${source_dav}/${root}/${versioned_file}")"
target_fileid="$(fileid_for "${target_dav}/${root}/${versioned_file}")"
test -n "${source_fileid}"
test -n "${target_fileid}"

source_versions_count="$(version_count_for "${source_versions_dav}" "${source_fileid}")"
source_trash_count="$(trash_count_for "${source_trash_dav}" "${trash_file}")"
target_versions_count="$(version_count_for "${target_versions_dav}" "${target_fileid}")"
target_trash_count="$(trash_count_for "${target_trash_dav}" "${trash_file}")"

test "${source_versions_count}" -ge 1
test "${source_trash_count}" -ge 1
test "${target_trash_count}" -eq 0

php occ files:scan "${SMOKE_USER}" --path="${SMOKE_USER}/files/${root}" >/tmp/nextcloud-history-smoke-scan.txt
cat /tmp/nextcloud-history-smoke-scan.txt

printf 'history_metadata_result user=%s root=%s source_versions=%s source_trash=%s target_versions=%s target_trash=%s sha256=%s\n' \
  "${SMOKE_USER}" "${root}" "${source_versions_count}" "${source_trash_count}" "${target_versions_count}" "${target_trash_count}" "${target_sha}"

if [ "${target_versions_count}" -gt 0 ]; then
  echo "target_versions_created_by_import=true"
else
  echo "target_versions_created_by_import=false"
fi
REMOTE

unset password
