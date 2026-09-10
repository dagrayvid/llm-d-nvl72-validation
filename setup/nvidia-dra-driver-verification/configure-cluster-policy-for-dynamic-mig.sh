#!/usr/bin/env bash

set -ex
set -o pipefail

oc patch clusterpolicy gpu-cluster-policy --type=merge -p '{
  "spec": {
    "devicePlugin": {"enabled": false},
    "mig": {"strategy": "none"},
    "cdi": {"enabled": true},
    "migManager": {"enabled": false}
  }
}'
