#!/usr/bin/env bash

set -ex
set -o pipefail

echo "Enable device plugin on worker nodes (true/false): $1"
for node in $(oc get node -l node-role.kubernetes.io/worker -o name); do
    oc label $node nvidia.com/gpu.deploy.device-plugin=$1 --overwrite
done
