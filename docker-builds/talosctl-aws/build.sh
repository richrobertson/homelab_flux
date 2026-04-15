#!/usr/bin/env bash
# Build and push the talosctl-aws helper image.
# Usage: ./build.sh [--push] [--tag <tag>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TALOS_VERSION="${TALOS_VERSION:-v1.12.6}"
IMAGE_NAME="${IMAGE_NAME:-oci.trueforge.org/homelab/talosctl-aws}"
IMAGE_TAG="${IMAGE_TAG:-${TALOS_VERSION}}"
PUSH_IMAGE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)  PUSH_IMAGE=true; shift ;;
    --tag)   IMAGE_TAG="$2"; shift 2 ;;
    *)       echo "Unknown option: $1"; exit 1 ;;
  esac
done

FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building ${FULL_IMAGE} ..."
docker build \
  --build-arg TALOS_VERSION="${TALOS_VERSION}" \
  -t "${FULL_IMAGE}" \
  "${SCRIPT_DIR}"

if [[ "${PUSH_IMAGE}" == true ]]; then
  echo "Pushing ${FULL_IMAGE} ..."
  docker push "${FULL_IMAGE}"
fi

echo "Done."
