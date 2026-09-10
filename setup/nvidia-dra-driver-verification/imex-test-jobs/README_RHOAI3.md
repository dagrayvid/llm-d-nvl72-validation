## Running nvbandwidth on RHOAI 3.0 with 3 nodes x 4 B200 GPUs (Grace CPUs)

### Changes for RHOAI 3.0

  - Added config file nvbandwidth-3nodes-4gpus.yaml
  - Since RHOAI comes with mpi-operator with the v1 API, changed the yaml to use v1 instead of v2
  - Since the kubectl being injected by the mpi-operator is x86_64, added init container to overlay it with the arm64 version
  - Adds `install-kubectl` and `wait-for-workers` init containers (launcher) and `install-kubectl`, `sshd-config` (workers).
  - Adds `kubectl-bin` and `sshd-config` volumes and corresponding mounts.

### HOWTO

```bash
git clone https://github.com/empovit/nvidia-dra-driver-verification.git
cd nvidia-dra-driver-verification/imex-test-jobs/

oc delete project imex-multi-node-gpu-test
oc apply -f nvbandwidth-3nodes-4gpus.yaml 

# Wait for the job to finish
oc logs -f -n imex-multi-node-gpu-test nvbandwidth-test-launcher
```

Example tail output:

```text
Defaulted container "mpi-launcher" out of: mpi-launcher, install-kubectl (init), wait-for-workers (init), kubectl-delivery (init)
memcpy CE GPU(row) -> GPU(column) bandwidth (GB/s)
           0         1         2         3         4         5         6         7         8         9        10        11
 0       N/A    820.51    821.30    822.08    820.83    821.14    821.37    821.14    821.85    821.06    821.77    820.75
 1    820.98       N/A    821.37    821.92    820.83    821.45    821.14    821.69    821.61    821.06    822.00    820.43
 2    820.67    820.75       N/A    821.69    820.75    821.06    820.51    820.83    821.22    820.51    821.61    820.12
 3    820.51    821.06    821.45       N/A    820.90    821.37    821.61    821.30    822.00    821.37    821.77    820.20
 4    821.06    821.06    821.45    822.08       N/A    821.45    821.30    821.45    822.24    821.30    822.08    820.12
 5    820.75    820.90    821.06    822.00    820.90       N/A    820.75    821.14    821.30    820.90    821.69    820.28
 6    820.12    820.98    821.53    821.85    820.67    820.83       N/A    820.98    821.53    821.37    821.06    820.20
 7    820.59    820.59    821.30    821.45    821.22    821.37    821.22       N/A    821.30    820.98    821.22    819.65
 8    820.98    820.98    821.37    821.77    820.83    821.14    821.22    821.61       N/A    820.75    821.37    820.04
 9    820.43    821.06    821.53    821.77    820.83    820.98    821.37    821.37    821.85       N/A    821.45    820.20
10    820.51    820.35    821.22    821.30    820.75    821.14    820.98    820.90    821.06    820.67       N/A    820.28
11    820.28    821.06    821.37    821.69    820.90    821.37    821.14    821.14    821.77    821.69    821.30       N/A

SUM multinode_device_to_device_memcpy_read_ce 108388.58

NOTE: The reported results may not reflect the full capabilities of the platform.
Performance can vary with software drivers, hardware clocks, and system topology.
```


