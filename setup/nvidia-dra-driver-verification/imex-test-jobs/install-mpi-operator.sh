#!/usr/bin/env bash

set -e
set -o pipefail

oc create -f https://github.com/kubeflow/mpi-operator/releases/download/v0.6.0/mpi-operator.yaml