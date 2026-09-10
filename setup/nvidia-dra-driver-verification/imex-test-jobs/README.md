# NVIDIA DRA Driver for Multi-Node NVLink

This directory contains test jobs for validating the IMEX (Internode Memory Exchange) support in [NVIDIA Dynamic Resource Allocation (DRA) driver](https://github.com/kubernetes-sigs/dra-driver-nvidia-gpu/). The test jobs use [nvbandwidth](https://github.com/NVIDIA/nvbandwidth) as a sample distributed workload to illustrate inter-GPU memory access, and validate the high bandwidth of NVLink communication channels.

## Prerequisites

### 1. GPU Allocation

The test jobs use the classic GPU allocation mechanism via an extended Kubernetes resource, and therefore require the device plugin to be enabled in the NVIDIA GPU operator.

### 2. MPI Operator

All test jobs require the [Kubeflow MPI Operator](https://github.com/kubeflow/mpi-operator) to orchestrate distributed MPI workloads:

```bash
# Install MPI Operator
./install-mpi-operator.sh
```

See [MPI Operator User Guide](https://github.com/kubeflow/mpi-operator/blob/master/README.md) for more information.

### 3. OpenShift Security Limitation

MPIJob containers run SSH daemons for inter-node communication, but OpenShift's default `restricted` SCC assigns random UIDs that prevent SSH daemon from functioning properly. An easy solution used in the test jobs is to run MPIJob with a service account assigned the `anyuid` SCC. **This is already implement in the job manifests.**


### 4. NVLink Partition

All cluster nodes must have the same clique ID, indicated by the `nvidia.com/gpu.clique` node label.

A **Clique ID** is a unique identifier that defines which GPUs are physically capable of communicating with each other over NVLink within an NVLink Domain. The partitioning of GPUs into cliques happens at the NVSwitch layer, and an IMEX domain must be formed around nodes that are within the same NVLink partition (clique). All GPUs on a given node are expected to have the same Clique ID, and multi-node communication requires all participating nodes to share the same clique.

```bash
# Verify all nodes have the same clique ID
oc get nodes -o custom-columns=NAME:".metadata.name",CLIQUE:".metadata.labels.nvidia\.com/gpu\.clique"
```

### 5. NVIDIA DRA Driver

Ensure the NVIDIA DRA driver is properly installed and configured in your cluster. See the main project documentation for installation instructions.

## Test Job Architecture

Each test job consists of two main Kubernetes resources that work together to run a multi-node nvbandwidth test across GPU nodes in a cluster.

### 1. ComputeDomain Resource

```yaml
apiVersion: resource.nvidia.com/v1beta1
kind: ComputeDomain
metadata:
  name: nvbandwidth-test-compute-domain
spec:
  numNodes: 2
  channel:
    resourceClaimTemplate:
      name: nvbandwidth-test-compute-domain-channel
```

**Purpose**: This defines a custom NVIDIA resource that establishes an IMEX channel for multi-node GPU communication.

**Key fields**:
- `numNodes: 2`: Specifies that this compute domain spans exactly 2 nodes
- `channel.resourceClaimTemplate.name`: Creates a template for resource claims that will enable high-performance communication channels between GPUs across the nodes

### 2. MPIJob Resource

```yaml
apiVersion: kubeflow.org/v2beta1
kind: MPIJob
```

**Purpose**: This defines an MPI (Message Passing Interface) job that orchestrates the distributed nvbandwidth test across multiple nodes.

#### MPIJob Specification

```yaml
spec:
  slotsPerWorker: 4
  launcherCreationPolicy: WaitForWorkersReady
  runPolicy:
    cleanPodPolicy: Running
  sshAuthMountPath: /home/mpiuser/.ssh
```

- `slotsPerWorker: 4`: Each worker node will use 4 GPU "slots" (4 GPUs per node)
- `launcherCreationPolicy: WaitForWorkersReady`: The launcher pod won't start until all worker pods are ready
- `cleanPodPolicy: Running`: Only clean up pods that are currently running (not failed/completed ones)
- `sshAuthMountPath`: MPI uses SSH for inter-node communication; this specifies where SSH keys are mounted

#### Launcher Configuration

The launcher is the "master" node that coordinates the MPI job:

**Node Affinity**:
```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
```
- Forces the launcher to run on a control plane node (master node)
- This separates orchestration from compute workloads

**Container Configuration**:
- `image: ghcr.io/nvidia/k8s-samples:nvbandwidth-v0.7-8d103163`: Uses NVIDIA's nvbandwidth testing image
- `runAsUser: 1000`: Runs as non-root user for security

**MPI Command**:
```yaml
command: [mpirun]
args:
  - --bind-to core
  - --map-by ppr:4:node
  - -np "8"
  - --report-bindings
  - -q
  - nvbandwidth
  - -t multinode_device_to_device_memcpy_read_ce
```

**MPI Arguments Explained**:
- `--bind-to core`: Bind MPI processes to CPU cores for consistent performance
- `--map-by ppr:4:node`: Map 4 processes per node (matches 4 GPUs per node)
- `-np "8"`: Total of 8 MPI processes (4 processes × 2 nodes)
- `--report-bindings`: Show which cores processes are bound to
- `-q`: Quiet mode (reduce verbose output)
- `nvbandwidth`: The actual bandwidth testing program
- `-t multinode_device_to_device_memcpy_read_ce`: Test type for multi-node device-to-device memory copy operations using Copy Engine

#### Worker Configuration

The workers are the compute nodes that actually run the bandwidth tests:

**Replica Configuration**:
- `replicas: 2`: Creates 2 worker pods (one per node)

**Pod Affinity**:
```yaml
affinity:
  podAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: nvbandwidth-test-replica
          operator: In
          values: [mpi-worker]
      topologyKey: nvidia.com/gpu.clique
```
- Ensures worker pods are scheduled on nodes with GPUs in the same "clique"
- `nvidia.com/gpu.clique`: A topology key that groups nodes with high-bandwidth GPU interconnects

**Container Configuration**:
- Same base image as launcher
- `command: [/usr/sbin/sshd]` with args `[-De, -f, /home/mpiuser/.sshd_config]`: Runs SSH daemon for MPI communication

**Resource Requirements**:
```yaml
resources:
  limits:
    nvidia.com/gpu: 4
  claims:
  - name: compute-domain-channel
```
- Requests exactly 4 GPUs per worker node
- Claims the compute domain channel for inter-node GPU communication

**Resource Claims**:
```yaml
resourceClaims:
- name: compute-domain-channel
  resourceClaimTemplateName: nvbandwidth-test-compute-domain-channel
```
- Links back to the ComputeDomain resource defined at the beginning
- This enables the DRA system to set up proper GPU-to-GPU communication channels

### How It All Works Together

1. **ComputeDomain** sets up a 2-node GPU communication domain with optimized channels
2. **MPIJob launcher** coordinates the distributed test from a control plane node
3. **MPI workers** (2 replicas) each claim 4 GPUs and join the compute domain
4. **MPI processes** (8 total: 4 per node) perform bandwidth tests between GPUs across nodes
5. **Test type** `multinode_device_to_device_memcpy_read_ce` specifically measures GPU-to-GPU memory transfer performance across nodes using Copy Engine

This setup is designed to validate that NVIDIA's DRA driver properly enables high-performance, multi-node GPU communication for demanding HPC and AI workloads.

## Running Test Jobs


1. Install Prerequisites

   ```bash
   # Install MPI Operator
   ./install-mpi-operator.sh
   ```

2. Deploy a Test Job


    Multi-node test on 2 nodes, 4 GPUs each:

    ```bash
    oc apply -f nvbandwidth-2nodes-4gpus.yaml
    ```

    Multi-node test on 3 nodes, 1 GPU each:

    ```bash
    oc apply -f nvbandwidth-3nodes-1gpu.yaml
    ```

3. Monitor Test Execution

   ```bash
   # Watch job status
   oc get mpijobs -w -n imex-multi-node-gpu-test

   # View launcher logs
   oc logs -f <launcher-pod-name> -n imex-multi-node-gpu-test

   # Monitor worker pods
   oc get pods -l nvbandwidth-test-replica=mpi-worker -n imex-multi-node-gpu-test
   ```

## Additional Resources

- [Testing Multi-Node NVLink support on GB200](https://github.com/NVIDIA/k8s-dra-driver-gpu/discussions/249)
- [nvbandwidth](https://github.com/NVIDIA/nvbandwidth)
- [NVIDIA IMEX Service for NVLink Networks](https://docs.nvidia.com/multi-node-nvlink-systems/imex-guide/index.html)
- [Multinode NVLink User Guide](https://docs.nvidia.com/multi-node-nvlink-systems/mnnvl-user-guide/index.html)
- [Kubeflow MPI Operator Documentation](https://github.com/kubeflow/mpi-operator/blob/master/README.md)