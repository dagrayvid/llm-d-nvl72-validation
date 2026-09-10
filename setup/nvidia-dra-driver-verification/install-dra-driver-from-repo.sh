#!/usr/bin/env bash

set -e
set -x

DRA_DRIVER_VERSION=${DRA_DRIVER_VERSION:-"0.4.0"}

GPU_HELM_OPTIONS=""
if [ "${DYNAMIC_MIG:-false}" = true ] || [ "${FORCE_GPU_SUPPORT:-false}" = true ]; then
    GPU_HELM_OPTIONS="--set resources.gpus.enabled=true --set gpuResourcesEnabledOverride=true"
else
    GPU_HELM_OPTIONS="--set resources.gpus.enabled=false"
fi

helm install dra-driver-nvidia-gpu \
    oci://registry.k8s.io/dra-driver-nvidia/charts/dra-driver-nvidia-gpu \
    --version="${DRA_DRIVER_VERSION}" \
    --create-namespace \
    --namespace dra-driver-nvidia-gpu \
    --set nvidiaDriverRoot=/run/nvidia/driver \
    --set featureGates.DynamicMIG="${DYNAMIC_MIG:-false}" \
    ${GPU_HELM_OPTIONS}
