#!/bin/bash
# Test VAAPI functionality in custom Plex image
# Usage: ./test-plex-vaapi.sh [--local|--k8s] [--image <image>]

set -euo pipefail

MODE="k8s"
IMAGE="${IMAGE:-oci.trueforge.org/homelab/plex-vaapi:latest}"
DOCKER_CMD="docker"

# Determine Docker/Podman command
if ! command -v docker &> /dev/null; then
  if command -v podman &> /dev/null; then
    DOCKER_CMD="podman"
  else
    echo "Error: Neither docker nor podman found"
    exit 1
  fi
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --local)
      MODE="local"
      shift
      ;;
    --k8s)
      MODE="k8s"
      shift
      ;;
    --image)
      IMAGE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "=== Testing Plex VAAPI Image ==="
echo "Mode: ${MODE}"
echo "Image: ${IMAGE}"
echo

# VAAPI test command - minimal transcoding that exercises libva
TEST_CMD='
echo "=== Checking VAAPI libraries ==="
ls -la /usr/lib/plexmediaserver/lib/libva* /usr/lib/plexmediaserver/lib/libdrm* 2>&1 | head -20
echo
echo "=== Checking system VAAPI support ==="
vainfo --display drm --device /dev/dri/renderD128 2>&1 | head -30 || echo "vainfo failed"
echo
echo "=== Testing Plex Transcoder VAAPI init ==="
"/usr/lib/plexmediaserver/Plex Transcoder" -v error \
  -f lavfi -i testsrc2=size=128x72:rate=1 -t 1 \
  -init_hw_device vaapi=va:/dev/dri/renderD128 \
  -vf format=nv12,hwupload \
  -c:v h264_vaapi \
  -f null - 2>&1 | head -40
echo
echo "=== Test complete ==="
'

if [ "${MODE}" = "local" ]; then
  echo "Running local Docker test container..."
  echo
  
  ${DOCKER_CMD} run --rm \
    --device /dev/dri/renderD128:/dev/dri/renderD128 \
    --device /dev/dri/card0:/dev/dri/card0 \
    "${IMAGE}" \
    bash -c "${TEST_CMD}"
    
elif [ "${MODE}" = "k8s" ]; then
  echo "Creating temporary test pod in Kubernetes..."
  echo
  
  # Check kubectl
  if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found"
    exit 1
  fi
  
  # Assume kubeconfig is configured
  if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config.stage"
  fi
  
  POD_NAME="plex-vaapi-test-$(date +%s)"
  
  # Create test pod with GPU device plugin allocation
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: default
spec:
  nodeSelector:
    kubernetes.io/hostname: k8s-stg-worker-0
  restartPolicy: Never
  containers:
    - name: test
      image: ${IMAGE}
      command: ["/bin/bash", "-c"]
      args:
        - |
          ${TEST_CMD}
          sleep 2
      resources:
        limits:
          gpu.intel.com/i915: "1"
        requests:
          gpu.intel.com/i915: "1"
      securityContext:
        runAsUser: 568
        runAsGroup: 568
        runAsNonRoot: true
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
      volumeMounts:
        - name: tmp
          mountPath: /tmp
  volumes:
    - name: tmp
      emptyDir: {}
EOF

  echo "Waiting for pod to complete..."
  kubectl -n default wait pod/${POD_NAME} --for=condition=Ready --timeout=120s 2>/dev/null || true
  
  # Wait a bit for execution
  sleep 5
  
  echo "Pod output:"
  kubectl -n default logs ${POD_NAME} --tail=200 || echo "Log retrieval failed"
  
  echo
  echo "Cleaning up..."
  kubectl -n default delete pod/${POD_NAME} --ignore-not-found >/dev/null 2>&1
  
  echo "✓ Test complete"
fi
