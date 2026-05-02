#!/usr/bin/env bash
set -euo pipefail

if [[ -f "${HOME}/.bash_profile" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.bash_profile" >/dev/null 2>&1
fi

KUBE_CONTEXT="${KUBE_CONTEXT:-admin@staging}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-nextcloud}"
TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-nextcloud-migration-clean}"
TARGET_SERVICE_URL="${TARGET_SERVICE_URL:-http://127.0.0.1}"
EXPECTED_MODULE="${EXPECTED_MODULE:-OC_DEFAULT_MODULE}"

run_id="$(date +%Y%m%d-%H%M%S)"

kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" exec -i "deploy/${TARGET_DEPLOYMENT}" -c nextcloud -- \
  env \
    VALIDATION_RUN_ID="${run_id}" \
    TARGET_SERVICE_URL="${TARGET_SERVICE_URL}" \
    EXPECTED_MODULE="${EXPECTED_MODULE}" \
    sh -s <<'REMOTE'
set -eu

status="$(php occ encryption:status)"
printf '%s\n' "${status}"
printf '%s\n' "${status}" | grep -q 'enabled: true'
printf '%s\n' "${status}" | grep -q "defaultModule: ${EXPECTED_MODULE}"

test -d /var/www/html/data/files_encryption
test -d "/var/www/html/data/files_encryption/${EXPECTED_MODULE}"
find "/var/www/html/data/files_encryption/${EXPECTED_MODULE}" -maxdepth 1 -name 'master_*.privateKey' | grep -q .
find "/var/www/html/data/files_encryption/${EXPECTED_MODULE}" -maxdepth 1 -name 'master_*.publicKey' | grep -q .

user="${NEXTCLOUD_ADMIN_USER}"
pass="${NEXTCLOUD_ADMIN_PASSWORD}"
folder="encryption-target-validation-${VALIDATION_RUN_ID}"
file="encrypted-at-rest-${VALIDATION_RUN_ID}.txt"
payload="Nextcloud encryption target validation ${VALIDATION_RUN_ID}\nmodule=${EXPECTED_MODULE}\n"
dav="${TARGET_SERVICE_URL}/remote.php/dav/files/${user}"
raw_path="/var/www/html/data/${user}/files/${folder}/${file}"

curl -fsS -u "${user}:${pass}" -X MKCOL "${dav}/${folder}" >/dev/null || true
printf '%b' "${payload}" | curl -fsS -u "${user}:${pass}" -T - "${dav}/${folder}/${file}" >/dev/null

expected_sha="$(printf '%b' "${payload}" | sha256sum | awk '{print $1}')"
webdav_sha="$(curl -fsS -u "${user}:${pass}" "${dav}/${folder}/${file}" | sha256sum | awk '{print $1}')"

if [ "${expected_sha}" != "${webdav_sha}" ]; then
  echo "webdav_plaintext_checksum_mismatch" >&2
  exit 1
fi

test -f "${raw_path}"
if ! head -c 96 "${raw_path}" | grep -q "HBEGIN:oc_encryption_module:${EXPECTED_MODULE}"; then
  echo "raw_target_file_missing_nextcloud_encryption_header raw_path=${raw_path}" >&2
  exit 1
fi

if grep -q 'Nextcloud encryption target validation' "${raw_path}"; then
  echo "raw_target_file_contains_plaintext raw_path=${raw_path}" >&2
  exit 1
fi

php occ files:scan "${user}" --path="${user}/files/${folder}" >/tmp/nextcloud-encryption-target-scan.txt
cat /tmp/nextcloud-encryption-target-scan.txt

printf 'encryption_target_validation_ok user=%s path=%s/%s sha256=%s\n' \
  "${user}" "${folder}" "${file}" "${webdav_sha}"
REMOTE
