#!/usr/bin/env bash

set -e

CONTAINER_CMD="${CONTAINER_CMD:-podman}"
IMAGE_NAME="${IMAGE_NAME:-nvbandwidth}"
IMAGE_REGISTRY="${IMAGE_REGISTRY:-localhost}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE="${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

${CONTAINER_CMD} build -t ${FULL_IMAGE} -f Containerfile.nvbandwidh .
