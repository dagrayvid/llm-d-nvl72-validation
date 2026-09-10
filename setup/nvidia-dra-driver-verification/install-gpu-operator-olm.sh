#!/usr/bin/env bash

set -ex
set -o pipefail

export GPU_OPERATOR_NAMESPACE="nvidia-gpu-operator"

oc apply -f gpu-operator-resources.yaml

sleep 15

timeout 120s bash -c "until oc get csv -n ${GPU_OPERATOR_NAMESPACE} -o name; do sleep 10; done"
CSV_NAME=$(oc get csv -n ${GPU_OPERATOR_NAMESPACE} -o name -l operators.coreos.com/gpu-operator-certified.nvidia-gpu-operator)
oc wait --for=jsonpath='{.status.reason}'=InstallSucceeded --timeout=360s -n ${GPU_OPERATOR_NAMESPACE} ${CSV_NAME}

timeout 60s bash -c "until oc get deployment gpu-operator -n ${GPU_OPERATOR_NAMESPACE} -o name; do sleep 10; done"
oc rollout status deployment gpu-operator -n ${GPU_OPERATOR_NAMESPACE}

CLUSTER_POLICY=$(oc get ${CSV_NAME} -n ${GPU_OPERATOR_NAMESPACE} -o jsonpath='{.metadata.annotations.alm-examples}' | jq -r 'map(select(.kind == "ClusterPolicy")) | .[0]')
oc apply -f - <<EOF
$CLUSTER_POLICY
EOF
