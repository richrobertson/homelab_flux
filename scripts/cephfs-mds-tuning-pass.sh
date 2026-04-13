#!/usr/bin/env bash
set -euo pipefail

# Low-risk CephFS MDS tuning pass for external cluster.
# Default mode is validate-only. Use --apply to set tuning values.

SSH_TARGET="root@pve3"
SSH_OPTS=(-o BatchMode=yes)
FS_NAME="kubernetes-prod-cephfs"

MDS_BAL_IDLE_THRESHOLD="0.0"
MDS_BAL_INTERVAL="5"
STANDBY_COUNT_WANTED="1"

APPLY=false

if [[ "${1:-}" == "--apply" ]]; then
  APPLY=true
fi

run_remote() {
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$@"
}

echo "== CephFS MDS Tuning Pass =="
echo "target=${SSH_TARGET} fs=${FS_NAME} apply=${APPLY}"

echo
echo "-- Baseline status --"
run_remote "ceph fs status"
echo "---"
run_remote "ceph mds stat"
echo "---"
run_remote "ceph fs get ${FS_NAME} | egrep 'max_mds|balancer|standby_count_wanted'"
echo "---"
run_remote "ceph config dump | egrep 'mds_bal_idle_threshold|mds_bal_interval' || true"

if [[ "$APPLY" == "true" ]]; then
  echo
  echo "-- Applying low-risk tuning --"
  run_remote "ceph config set mds mds_bal_idle_threshold ${MDS_BAL_IDLE_THRESHOLD}"
  run_remote "ceph config set mds mds_bal_interval ${MDS_BAL_INTERVAL}"
  run_remote "ceph fs set ${FS_NAME} standby_count_wanted ${STANDBY_COUNT_WANTED}"
fi

echo
echo "-- Validation checks --"
run_remote "ceph config dump | egrep 'mds_bal_idle_threshold|mds_bal_interval'"
run_remote "ceph fs get ${FS_NAME} | egrep 'max_mds|balancer|standby_count_wanted'"
echo "---"
run_remote "ceph tell mds.pve3a perf dump | egrep -i 'request|reply|slow_reply|subtrees|queue_len' | head -n 80"
echo "---"
run_remote "ceph tell mds.pve5a perf dump | egrep -i 'request|reply|slow_reply|subtrees|queue_len' | head -n 80"

cat <<'EOF'

Rollback commands (if needed):
  ceph config rm mds mds_bal_idle_threshold
  ceph config rm mds mds_bal_interval
  ceph fs set kubernetes-prod-cephfs standby_count_wanted 0

Recommended post-change checks (5-15 min):
  ceph fs status
  ceph tell mds.pve3a perf dump | egrep -i 'slow_reply|queue_len' | head
  ceph tell mds.pve5a perf dump | egrep -i 'slow_reply|queue_len' | head
EOF
