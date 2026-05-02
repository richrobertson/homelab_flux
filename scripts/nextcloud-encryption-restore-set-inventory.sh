#!/usr/bin/env bash
set -euo pipefail

if [[ -f "${HOME}/.bash_profile" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.bash_profile" >/dev/null 2>&1
fi

KUBE_CONTEXT="${KUBE_CONTEXT:-admin@staging}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-nextcloud}"
TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-nextcloud-migration-clean}"
TARGET_CNPG_CLUSTER="${TARGET_CNPG_CLUSTER:-nextcloud-migration-clean-cnpg}"
TARGET_DB_APP_SECRET="${TARGET_DB_APP_SECRET:-nextcloud-migration-clean-cnpg-app}"
EXPECTED_MODULE="${EXPECTED_MODULE:-OC_DEFAULT_MODULE}"

echo "context=${KUBE_CONTEXT}"
echo "namespace=${TARGET_NAMESPACE}"
echo "deployment=${TARGET_DEPLOYMENT}"
echo "cnpg_cluster=${TARGET_CNPG_CLUSTER}"
echo "db_app_secret=${TARGET_DB_APP_SECRET}"

echo "--- flux/workload ---"
kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" get deploy "${TARGET_DEPLOYMENT}" \
  -o jsonpath='{.status.readyReplicas}/{.status.replicas} ready{"\n"}'
kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" get cluster "${TARGET_CNPG_CLUSTER}" \
  -o jsonpath='{.status.phase}{" primary="}{.status.currentPrimary}{"\n"}'

echo "--- database secret keys ---"
kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" get secret "${TARGET_DB_APP_SECRET}" -o json | \
  jq -r '.data | keys[]' | sort

echo "--- encryption and key material ---"
kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" exec -i "deploy/${TARGET_DEPLOYMENT}" -c nextcloud -- \
  env EXPECTED_MODULE="${EXPECTED_MODULE}" sh -s <<'REMOTE'
set -eu

status="$(php occ encryption:status)"
printf '%s\n' "${status}"
printf '%s\n' "${status}" | grep -q 'enabled: true'
printf '%s\n' "${status}" | grep -q "defaultModule: ${EXPECTED_MODULE}"

config_file="/var/www/html/config/config.php"
test -s "${config_file}"
php -r '
  include "/var/www/html/config/config.php";
  if (!isset($CONFIG["secret"]) || $CONFIG["secret"] === "") {
    fwrite(STDERR, "missing_nextcloud_config_secret\n");
    exit(1);
  }
  echo "config_secret_present=true\n";
'

key_root="/var/www/html/data/files_encryption/${EXPECTED_MODULE}"
test -d "${key_root}"
master_private_count="$(find "${key_root}" -maxdepth 1 -type f -name 'master_*.privateKey' | wc -l | awk '{print $1}')"
master_public_count="$(find "${key_root}" -maxdepth 1 -type f -name 'master_*.publicKey' | wc -l | awk '{print $1}')"
pubshare_private_count="$(find "${key_root}" -maxdepth 1 -type f -name 'pubShare_*.privateKey' | wc -l | awk '{print $1}')"
pubshare_public_count="$(find "${key_root}" -maxdepth 1 -type f -name 'pubShare_*.publicKey' | wc -l | awk '{print $1}')"

test "${master_private_count}" -ge 1
test "${master_public_count}" -ge 1

printf 'master_private_keys=%s\n' "${master_private_count}"
printf 'master_public_keys=%s\n' "${master_public_count}"
printf 'pubshare_private_keys=%s\n' "${pubshare_private_count}"
printf 'pubshare_public_keys=%s\n' "${pubshare_public_count}"

find /var/www/html/data -path '*/files_encryption/*' -type f -printf '.' | wc -c | awk '{print "files_encryption_file_count=" $1}'
du -sh /var/www/html/data/files_encryption /var/www/html/data/*/files_encryption 2>/dev/null | sort

sample="$(find /var/www/html/data -path '*/files/*' -type f ! -path '*/files_encryption/*' | head -1)"
test -n "${sample}"
if ! head -c 96 "${sample}" | grep -q "HBEGIN:oc_encryption_module:${EXPECTED_MODULE}"; then
  echo "sample_raw_file_missing_encryption_header path=${sample}" >&2
  exit 1
fi
echo "sample_raw_file_encrypted=true"
REMOTE

echo "--- required restore set ---"
cat <<EOF
The encrypted restore set must be captured and restored together:
- CNPG database dump or backup for ${TARGET_CNPG_CLUSTER}
- /var/www/html/config/config.php, including the Nextcloud config secret
- Kubernetes secrets used by the app and database, including ${TARGET_DB_APP_SECRET}
- /var/www/html/data/files_encryption and each user's files_encryption directory
- The encrypted user files on the Synology NFS PVC

This script intentionally does not print or copy secret values.
EOF
