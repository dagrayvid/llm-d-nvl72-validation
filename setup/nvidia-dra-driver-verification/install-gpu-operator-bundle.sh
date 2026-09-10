#!/usr/bin/env bash

set -e
set -o pipefail
set -o nounset

echo "Work around stale operator image when re-installing a bundle"
for node in $(oc get nodes -o name); do
  # The default bundle always points to the same GPU operator image, so just updating the
  # bundle image is not enough to update the operator.
  oc debug $node -- chroot /host crictl rmi ghcr.io/nvidia/gpu-operator:main-latest || true
done

"$(dirname "$0")/download-operator-sdk.sh"

echo "Bundle image: ${BUNDLE_IMAGE}"
export GPU_OPERATOR_NAMESPACE="nvidia-gpu-operator"

# Create namespace with pod-security label using oc apply
echo "Creating/updating namespace $GPU_OPERATOR_NAMESPACE with pod-security label"
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $GPU_OPERATOR_NAMESPACE
  labels:
    pod-security.kubernetes.io/enforce: privileged
EOF


"$(dirname "$0")/operator-sdk" run bundle --timeout=10m -n $GPU_OPERATOR_NAMESPACE --install-mode OwnNamespace ${BUNDLE_IMAGE}
