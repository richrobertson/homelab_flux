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
SMOKE_USER="${SMOKE_USER:-migration-dryrun}"
SMOKE_GROUP="${SMOKE_GROUP:-migration-dryrun}"

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
      --display-name "Migration Dry Run" \
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
    sh -s <<'REMOTE'
set -eu

root="migration-dryrun-script-${SMOKE_RUN_ID}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

mkdir -p "${tmp_dir}/nested"
printf 'Nextcloud WebDAV migration smoke test\nrun=%s\nsource=staging-s3-primary\ntarget=clean-synology-nfs\n' "${SMOKE_RUN_ID}" > "${tmp_dir}/README.txt"
printf 'Nested metadata-aware copy test\nuser=%s\n' "${SMOKE_USER}" > "${tmp_dir}/nested/notes.txt"
dd if=/dev/urandom of="${tmp_dir}/nested/random.bin" bs=1024 count=32 >/dev/null 2>&1

source_dav="${SOURCE_SERVICE_URL}/remote.php/dav/files/${SMOKE_USER}"
target_dav="${TARGET_SERVICE_URL}/remote.php/dav/files/${SMOKE_USER}"

mkcol() {
  curl -fsS -u "${SMOKE_USER}:${SMOKE_PASS}" -X MKCOL "$1" >/dev/null || true
}

upload() {
  curl -fsS -u "${SMOKE_USER}:${SMOKE_PASS}" -T "$1" "$2" >/dev/null
}

copy_via_webdav() {
  curl -fsS -u "${SMOKE_USER}:${SMOKE_PASS}" "$1" | \
    curl -fsS -u "${SMOKE_USER}:${SMOKE_PASS}" -T - "$2" >/dev/null
}

hash_url() {
  curl -fsS -u "${SMOKE_USER}:${SMOKE_PASS}" "$1" | sha256sum | awk '{print $1}'
}

mkcol "${source_dav}/${root}"
mkcol "${source_dav}/${root}/nested"
mkcol "${target_dav}/${root}"
mkcol "${target_dav}/${root}/nested"

upload "${tmp_dir}/README.txt" "${source_dav}/${root}/README.txt"
upload "${tmp_dir}/nested/notes.txt" "${source_dav}/${root}/nested/notes.txt"
upload "${tmp_dir}/nested/random.bin" "${source_dav}/${root}/nested/random.bin"

copy_via_webdav "${source_dav}/${root}/README.txt" "${target_dav}/${root}/README.txt"
copy_via_webdav "${source_dav}/${root}/nested/notes.txt" "${target_dav}/${root}/nested/notes.txt"
copy_via_webdav "${source_dav}/${root}/nested/random.bin" "${target_dav}/${root}/nested/random.bin"

for relpath in README.txt nested/notes.txt nested/random.bin; do
  source_sha="$(hash_url "${source_dav}/${root}/${relpath}")"
  target_sha="$(hash_url "${target_dav}/${root}/${relpath}")"
  if [ "${source_sha}" != "${target_sha}" ]; then
    echo "checksum_mismatch ${relpath}" >&2
    exit 1
  fi
  printf 'verified %s sha256=%s\n' "${relpath}" "${target_sha}"
done

test -f "/var/www/html/data/${SMOKE_USER}/files/${root}/README.txt"
test -f "/var/www/html/data/${SMOKE_USER}/files/${root}/nested/notes.txt"
test -f "/var/www/html/data/${SMOKE_USER}/files/${root}/nested/random.bin"

php occ files:scan "${SMOKE_USER}" --path="${SMOKE_USER}/files/${root}" >/tmp/nextcloud-webdav-smoke-scan.txt
cat /tmp/nextcloud-webdav-smoke-scan.txt

printf 'webdav_tree_import_ok user=%s root=%s\n' "${SMOKE_USER}" "${root}"
REMOTE

unset password
