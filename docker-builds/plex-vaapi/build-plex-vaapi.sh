#!/bin/bash
# Build and push custom Plex image with Ubuntu 24.04 VAAPI libraries
# Usage: ./build-plex-vaapi.sh [--push] [--tag <tag>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-oci.trueforge.org/homelab/plex-vaapi}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
PUSH_IMAGE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --push)
      PUSH_IMAGE=true
      shift
      ;;
    --tag)
      IMAGE_TAG="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

echo "=== Building Custom Plex Image with Ubuntu 24.04 VAAPI Libraries ==="
echo "Target: ${FULL_IMAGE}"
echo

# Check if Docker/podman is available
DOCKER_CMD="docker"
if ! command -v docker &> /dev/null; then
  if command -v podman &> /dev/null; then
    DOCKER_CMD="podman"
  else
    echo "Error: Neither docker nor podman found. Please install one."
    exit 1
  fi
fi

echo "Using: ${DOCKER_CMD}"
echo

# Build image
echo "Building image..."
"${DOCKER_CMD}" build -t "${FULL_IMAGE}" -f "${SCRIPT_DIR}/Dockerfile" "${SCRIPT_DIR}"

if [ $? -ne 0 ]; then
  echo "Error: Build failed"
  exit 1
fi

echo "✓ Build complete: ${FULL_IMAGE}"
echo

# Show image info
echo "Image info:"
"${DOCKER_CMD}" images | grep "plex-vaapi" | head -5

echo
echo "To test image locally:"
echo "  ${DOCKER_CMD} run --rm -it ${FULL_IMAGE} bash"
echo

# Push if requested
if [ "${PUSH_IMAGE}" = true ]; then
  echo "Pushing image to registry..."
  if ! "${DOCKER_CMD}" push "${FULL_IMAGE}"; then
    echo "Error: Push failed. Check registry credentials."
    exit 1
  fi
  echo "✓ Push complete: ${FULL_IMAGE}"
else
  echo "To push this image to registry, run:"
  echo "  ${DOCKER_CMD} push ${FULL_IMAGE}"
  echo "or"
  echo "  ./build-plex-vaapi.sh --push --tag ${IMAGE_TAG}"
fi
