#!/usr/bin/env bash

set -e
set -x

if ! go version; then
    echo "Go installation required"
    exit 1
fi

if [ -n "${DOCKER:-}" ] && [ "${DOCKER}" != "docker" ]; then
    echo "This script only works with Docker"
    exit 1
fi

set -o nounset
cd "${DRA_DRIVER_DIR}"

export REGISTRY=${REGISTRY:-quay.io/vemporop}
export IMAGE_TAG=$(git show --format=reference | head -1 | awk '{print $1}')
export PUSH_ON_BUILD=${PUSH_ON_BUILD:-true}
export BUILD_MULTI_ARCH_IMAGES=${BUILD_MULTI_ARCH_IMAGES:-true}

make -f deployments/container/Makefile build
