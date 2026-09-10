#!/usr/bin/env bash

set -e
set -x
set -o nounset

if [ -z "${DRA_DRIVER_DIR:-}" ]; then
    echo "Error: DRA_DRIVER_DIR is required (path to dra-driver-nvidia-gpu repository)"
    exit 1
fi

REGISTRY=${REGISTRY:-"nvcr.io/nvidia"}
TAG=${TAG:-"v0.4.0"}
IMAGE=${IMAGE:-"dra-driver-nvidia-gpu"}
FORCE_GPU_SUPPORT=${FORCE_GPU_SUPPORT:-false}

echo "DRA driver directory: ${DRA_DRIVER_DIR}"
echo "Image tag: ${TAG}"
echo "Image registry: ${REGISTRY}"
echo "Image name: ${IMAGE}"
echo "Force GPU support: ${FORCE_GPU_SUPPORT}"

GPU_HELM_OPTIONS=""
if [ "${DYNAMIC_MIG:-false}" = true ] || [ "${FORCE_GPU_SUPPORT}" = true ]; then
    GPU_HELM_OPTIONS="--set resources.gpus.enabled=true --set gpuResourcesEnabledOverride=true"
else
    GPU_HELM_OPTIONS="--set resources.gpus.enabled=false"
fi

# Override controller.affinity to allow scheduling on worker nodes
# By default, the controller requires control-plane nodes, but this cluster only has worker nodes
helm install dra-driver-nvidia-gpu ${DRA_DRIVER_DIR}/deployments/helm/dra-driver-nvidia-gpu \
    --create-namespace \
    --namespace dra-driver-nvidia-gpu \
    --set nvidiaDriverRoot=/run/nvidia/driver \
    --set featureGates.DynamicMIG="${DYNAMIC_MIG:-false}" \
    ${GPU_HELM_OPTIONS} \
    --set image.tag=${TAG} \
    --set image.repository=${REGISTRY}/${IMAGE}
