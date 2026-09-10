#!/usr/bin/env bash

set -e
set -o pipefail

export GPU_OPERATOR_NAMESPACE=${GPU_OPERATOR_NAMESPACE:-"nvidia-gpu-operator"}

"$(dirname "$0")/operator-sdk" cleanup gpu-operator-certified -n $GPU_OPERATOR_NAMESPACE
