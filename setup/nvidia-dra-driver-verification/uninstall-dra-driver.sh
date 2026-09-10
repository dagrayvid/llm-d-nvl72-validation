#!/bin/sh

set -ex

helm uninstall --namespace dra-driver-nvidia-gpu dra-driver-nvidia-gpu
