#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${HOME}/.bash_profile" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.bash_profile" >/dev/null 2>&1
fi

KUBE_CONTEXT="${KUBE_CONTEXT:-admin@staging}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-nextcloud}"
TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-nextcloud-migration-clean}"
SOURCE_NAMESPACE="${SOURCE_NAMESPACE:-default}"
SOURCE_DEPLOYMENT="${SOURCE_DEPLOYMENT:-nextcloud}"

run_step() {
  local name="$1"
  shift

  printf '\n==> %s\n' "${name}"
  "$@"
}

echo "Nextcloud migration validation suite"
echo "context=${KUBE_CONTEXT}"
echo "source=${SOURCE_NAMESPACE}/${SOURCE_DEPLOYMENT}"
echo "target=${TARGET_NAMESPACE}/${TARGET_DEPLOYMENT}"

run_step "target encryption validation" \
  "${script_dir}/nextcloud-encryption-target-validation.sh"

run_step "encrypted restore-set inventory" \
  "${script_dir}/nextcloud-encryption-restore-set-inventory.sh"

run_step "metadata-aware WebDAV tree copy" \
  "${script_dir}/nextcloud-webdav-migration-smoke-test.sh"

run_step "user and group share recreation" \
  "${script_dir}/nextcloud-share-migration-smoke-test.sh"

run_step "versions and trashbin boundary" \
  "${script_dir}/nextcloud-history-migration-smoke-test.sh"

printf '\nnextcloud_migration_validation_suite_ok\n'
