# NVIDIA DRA Driver Verification

This repository provides scripts and tools for verifying the [DRA Driver for NVIDIA GPUs](https://github.com/kubernetes-sigs/dra-driver-nvidia-gpu/) on OpenShift.

## Prerequisites

- OpenShift 4.21+ cluster with GPU nodes
- Cluster administrator privileges (`cluster-admin` role)
- `oc` CLI tool
- Helm 3.x (for DRA driver installation)

Verify that the DRA API is available on your cluster:

```bash
oc api-resources --api-group='resource.k8s.io'
```

## Installation Overview

1. Install the NVIDIA GPU operator for NVIDIA drivers and GPU allocation:
   * Install the Node Feature Discovery (NFD) operator and create a `NodeFeatureDiscovery` CR.
   * Install the NVIDIA GPU Operator and create a `ClusterPolicy` CR.
2. Install the NVIDIA DRA driver (version 0.4.0 or later) for DRA features.

## Setup Instructions

Follow these steps in order to get the NVIDIA DRA driver up and running in your cluster:

### 1. Install the NVIDIA GPU Operator

First, install the Node Feature Discovery (NFD) Operator:

```bash
./install-nfd-operator.sh
```

Then install the NVIDIA GPU Operator. Choose **one** of the following installation methods:

#### Option A: Using OLM (Operator Lifecycle Manager)

```bash
./install-gpu-operator-olm.sh
```

#### Option B: Using Bundle Installation

```bash
# Set the bundle image (required)
export BUNDLE_IMAGE="your-bundle-image:tag"
./install-gpu-operator-bundle.sh

# Example with pre-release version:
export BUNDLE_IMAGE="ghcr.io/nvidia/gpu-operator/gpu-operator-bundle:main-latest"
./install-gpu-operator-bundle.sh
```

**Note:** The `BUNDLE_IMAGE` environment variable is required for bundle installation.

#### Important: GPU Operator Upgrade Compatibility with DRA

When using DRA for GPU allocation (including dynamic MIG), there is a [known issue](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/dra-intro-install.html#known-issues) where the NVIDIA Driver Manager will not correctly evict the DRA driver kubelet plugin during GPU Operator driver upgrades. Without the configuration below, a GPU Operator upgrade will cause the driver daemonset pod to crash because the DRA driver holds the GPU, even when no workloads are running.

To avoid this, perform the following steps after installing the GPU Operator:

1. Label the GPU nodes that will use DRA GPU allocation:

   ```bash
   oc label node <gpu-node> nvidia.com/dra-kubelet-plugin=true
   ```

2. Configure the GPU Operator's `ClusterPolicy` to evict the DRA kubelet plugin during driver upgrades:

   ```bash
   oc patch clusterpolicy gpu-cluster-policy --type=merge -p '{
     "spec": {"driver": {"manager": {"env": [{"name": "NODE_LABEL_FOR_GPU_POD_EVICTION", "value": "nvidia.com/dra-kubelet-plugin"}]}}}
   }'
   ```

### 2. Install the NVIDIA DRA Driver

Choose **one** of the following installation methods:

#### Option A: Install from OCI Registry (Recommended)

```bash
# Use default version (0.4.0)
./install-dra-driver-from-repo.sh

# Or explicitly specify a version
export DRA_DRIVER_VERSION="0.4.0"
./install-dra-driver-from-repo.sh
```

#### Option B: Install from Local Build

```bash
# First build the driver image
export DRA_DRIVER_DIR="/path/to/dra-driver-nvidia-gpu"
export REGISTRY="your-registry.com/username"
export TAG="your-tag"
./build-dra-driver-image.sh

# Then install from local image
./install-dra-driver-from-local.sh
```

## Verification

After installation, verify that the DRA driver is working:

```bash
# Check DRA driver pods
oc get pods -n dra-driver-nvidia-gpu

# Check for available GPU resource classes
oc get resourceclass
```

## Dynamic MIG

See [dynamic-mig.md](dynamic-mig.md) for instructions on setting up and verifying dynamic MIG with the DRA driver.

## IMEX Multi-Node Tests

The [`imex-test-jobs`](imex-test-jobs/) directory contains validation tests for multi-node NVLink communication using NVIDIA IMEX channels.

## Documentation Links

- [DRA Driver for NVIDIA GPUs Repository](https://github.com/kubernetes-sigs/dra-driver-nvidia-gpu/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/index.html)
- [Kubernetes Dynamic Resource Allocation](https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/)
