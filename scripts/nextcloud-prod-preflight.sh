#!/usr/bin/env bash
set -euo pipefail

if [[ -f "${HOME}/.bash_profile" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.bash_profile" >/dev/null 2>&1
fi

KUBE_CONTEXT="${KUBE_CONTEXT:-admin@prod}"
SOURCE_NAMESPACE="${SOURCE_NAMESPACE:-default}"
SOURCE_DEPLOYMENT="${SOURCE_DEPLOYMENT:-nextcloud}"
SOURCE_CNPG_CLUSTER="${SOURCE_CNPG_CLUSTER:-nextcloud-cnpg}"
SOURCE_S3_SECRET="${SOURCE_S3_SECRET:-nextcloud-s3-secret}"

TARGET_NAMESPACE="${TARGET_NAMESPACE:-nextcloud}"
TARGET_PV="${TARGET_PV:-nextcloud-data-synology-nfs}"
TARGET_PVC="${TARGET_PVC:-nextcloud-data}"
EXPECTED_NFS_PATH="${EXPECTED_NFS_PATH:-/volume1/nextcloud-data-prod}"

WRITE_TEST_ENABLED="${WRITE_TEST_ENABLED:-true}"
WRITE_TEST_IMAGE="${WRITE_TEST_IMAGE:-busybox:1.36}"
WRITE_TEST_UID="${WRITE_TEST_UID:-33}"
WRITE_TEST_GID="${WRITE_TEST_GID:-33}"

section() {
  printf '\n== %s ==\n' "$1"
}

occ() {
  kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" exec "deploy/${SOURCE_DEPLOYMENT}" -c nextcloud -- php occ "$@"
}

objectstore_presence() {
  local tmp

  tmp="$(mktemp)"
  if occ config:system:get objectstore >"${tmp}" 2>/dev/null; then
    rm -f "${tmp}"
    echo "true"
  else
    rm -f "${tmp}"
    echo "false"
  fi
}

assert_equals() {
  local label="$1"
  local expected="$2"
  local actual="$3"

  if [[ "${actual}" != "${expected}" ]]; then
    printf '%s_expected=%s\n' "${label}" "${expected}" >&2
    printf '%s_actual=%s\n' "${label}" "${actual}" >&2
    exit 1
  fi
}

run_write_test() {
  local pod
  pod="nextcloud-prod-nfs-write-test-$(date +%Y%m%d%H%M%S)"

  cat <<EOF | kubectl --context "${KUBE_CONTEXT}" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${pod}
  namespace: ${TARGET_NAMESPACE}
  labels:
    app.kubernetes.io/name: nextcloud-prod-nfs-write-test
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: ${WRITE_TEST_UID}
    runAsGroup: ${WRITE_TEST_GID}
    fsGroup: ${WRITE_TEST_GID}
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: test
      image: ${WRITE_TEST_IMAGE}
      command:
        - sh
        - -c
        - |
          set -eu
          marker="/data/.prod-nfs-write-test"
          date -u +%Y-%m-%dT%H:%M:%SZ > "\${marker}"
          cat "\${marker}"
          rm -f "\${marker}"
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: ${TARGET_PVC}
EOF

  if ! kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" wait \
    --for=jsonpath='{.status.phase}'=Succeeded \
    "pod/${pod}" \
    --timeout=180s >/dev/null; then
    kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" logs "pod/${pod}" >&2 || true
    kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" delete pod "${pod}" --ignore-not-found=true --wait=true >/dev/null
    return 1
  fi
  printf 'write_test_timestamp='
  kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" logs "pod/${pod}"
  kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" delete pod "${pod}" --wait=true >/dev/null
}

echo "Nextcloud production migration preflight"
echo "context=${KUBE_CONTEXT}"
echo "source=${SOURCE_NAMESPACE}/${SOURCE_DEPLOYMENT}"
echo "target_pvc=${TARGET_NAMESPACE}/${TARGET_PVC}"
echo "printed_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

section "flux"
flux --context "${KUBE_CONTEXT}" -n flux-system get kustomizations | \
  awk 'NR == 1 || $1 ~ /^(apps|nextcloud-storage-target|infra-configs|infra-gateway)$/'

section "source nextcloud"
kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get deploy "${SOURCE_DEPLOYMENT}" \
  -o jsonpath='ready={.status.readyReplicas}/{.status.replicas}{"\n"}'
occ status
occ encryption:status || true
printf 'source_objectstore_config_present=%s\n' "$(objectstore_presence)"
printf 'source_s3_secret_keys=\n'
kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get secret "${SOURCE_S3_SECRET}" -o json | \
  jq -r '.data | keys[]' | sort | sed 's/^/  - /'

section "source database"
kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get cluster "${SOURCE_CNPG_CLUSTER}" \
  -o jsonpath='phase={.status.phase} primary={.status.currentPrimary} instances={.status.instances} ready={.status.readyInstances}{"\n"}'
kubectl --context "${KUBE_CONTEXT}" -n "${SOURCE_NAMESPACE}" get scheduledbackups.postgresql.cnpg.io,backups.postgresql.cnpg.io 2>/dev/null | \
  awk 'NR == 1 || /nextcloud/'

section "target storage"
pv_path="$(kubectl --context "${KUBE_CONTEXT}" get pv "${TARGET_PV}" -o jsonpath='{.spec.nfs.path}')"
pv_phase="$(kubectl --context "${KUBE_CONTEXT}" get pv "${TARGET_PV}" -o jsonpath='{.status.phase}')"
pvc_phase="$(kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" get pvc "${TARGET_PVC}" -o jsonpath='{.status.phase}')"
pvc_volume="$(kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" get pvc "${TARGET_PVC}" -o jsonpath='{.spec.volumeName}')"
assert_equals "target_nfs_path" "${EXPECTED_NFS_PATH}" "${pv_path}"
assert_equals "target_pv_phase" "Bound" "${pv_phase}"
assert_equals "target_pvc_phase" "Bound" "${pvc_phase}"
assert_equals "target_pvc_volume" "${TARGET_PV}" "${pvc_volume}"
printf 'target_nfs_path=%s\n' "${pv_path}"
printf 'target_pv_phase=%s\n' "${pv_phase}"
printf 'target_pvc_phase=%s\n' "${pvc_phase}"
printf 'target_pvc_volume=%s\n' "${pvc_volume}"

printf 'pods_mounting_target_pvc='
mounted_pods="$(kubectl --context "${KUBE_CONTEXT}" get pods -A -o json | \
  jq -r --arg claim "${TARGET_PVC}" --arg ns "${TARGET_NAMESPACE}" '
    [
      .items[]
      | select(.metadata.namespace == $ns)
      | select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName == $claim))
      | "\(.metadata.namespace)/\(.metadata.name)"
    ]
    | join(",")
  ')"
printf '%s\n' "${mounted_pods:-none}"
if [[ -n "${mounted_pods}" ]]; then
  echo "target PVC is already mounted; refusing write test" >&2
  exit 1
fi

if [[ "${WRITE_TEST_ENABLED}" == "true" ]]; then
  run_write_test
else
  echo "write_test_enabled=false"
fi

section "safety boundary"
cat <<'EOF'
- This preflight does not change the production Nextcloud deployment.
- This preflight does not remove S3 objectstore configuration.
- This preflight does not copy S3 objects or user files.
- The only write is an optional temporary marker on the target Synology NFS PVC.
EOF
