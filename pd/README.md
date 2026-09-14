# Prefill/decode validation

## DeepSeek-V4-Flash benchmarks

Benchmark results for `RedHatAI/DeepSeek-V4-Flash-NVFP4-FP8` on GB200 NVL72.
Each model-server Pod uses tensor parallelism across four GPUs (`TP=4`).

### GuideLLM

| Results directory | Workload | P/D topology |
| --- | --- | --- |
| `deepseek-v4-flash-1000-1000/` | 1,000 input tokens / 1,000 output tokens | 1 prefill Pod / 2 decode Pods (`1P/2D`) |
| `deepseek-v4-flash-8000-1000/` | 8,000 input tokens / 1,000 output tokens | 2 prefill Pods / 1 decode Pod (`2P/1D`) |

The raw `benchmarks.json` exports are intentionally ignored by Git. The CSV
summaries and collected server logs are retained in the corresponding results
directories.

### AgentX

These runs used two prefill Pods and one decode Pod (`2P/1D`) and the
`semianalysisai/cc-traces-weka-062126` dataset with subagents.

These are experimental benchmark results.

| Results directory | Concurrency | Run mode |
| --- | ---: | --- |
| `2ptp4-1dtp4-agentx-c8-smoke/` | 8 | Short smoke test (`unsafe_override`) |
| `2ptp4-1dtp4-agentx-c16/` | 16 | Standard-duration test |
| `2ptp4-1dtp4-agentx-c32/` | 32 | Standard-duration test |

## Multiple model pods on one ComputeDomain node

This workaround is not required merely because prefill and decode use different
tensor-parallel sizes. Heterogeneous TP is handled by vLLM/NIXL; for this hybrid
Nemotron model, `VLLM_SSM_CONV_STATE_LAYOUT=DS` also keeps the transferred Mamba
convolution state layout compatible between TP2 prefill and TP4 decode. The
shared claim is required because two separate TP2 prefill Pods are co-located on
one GB200 node and both need access to that node's ComputeDomain IMEX channel.

The ComputeDomain-generated channel `ResourceClaimTemplate` creates a distinct
channel claim for every Pod. With the NVIDIA DRA driver used in this cluster,
only one independently generated ComputeDomain channel claim can be allocated
on a node. Consequently, a workload using `resourceClaimTemplateName` for every
replica schedules at most one model Pod per node even when GPUs remain free.

Co-located Pods must instead share one named, node-local `ResourceClaim` through
`resourceClaimName`. The claim embeds the live ComputeDomain UID, so it becomes
invalid if the ComputeDomain is deleted and recreated. A single replica template
can share one claim only on one node; spreading co-located replicas over multiple
nodes requires separate, explicitly placed workloads and one shared claim per
node.

This behavior and workaround are described upstream:

- [NVIDIA DRA driver issue #309](https://github.com/kubernetes-sigs/dra-driver-nvidia-gpu/issues/309)
  identifies multiple Pods on one ComputeDomain node as a valid MNNVL use case
  and documents manually sharing the underlying `ResourceClaim` as the working
  approach.
- [NVIDIA DRA driver v25.3 release discussion #399](https://github.com/kubernetes-sigs/dra-driver-nvidia-gpu/discussions/399)
  describes the older one-Pod-per-ComputeDomain-node restriction and the work
  toward first-class multiple-Pod support. The behavior of the driver deployed
  on this validation cluster still requires the explicit shared-claim pattern.

The two-node Nemotron deployment demonstrates the supported arrangement:

- one TP4 decode Pod on `redhat-gb200-validation-gpu01`;
- two TP2 prefill Pods on `redhat-gb200-validation-gpu02`;
- one dynamically generated channel claim for decode;
- one named channel claim shared by both prefill Pods.

Create the DRA resources first:

```bash
oc delete llminferenceservice nemotron3-super-pd --ignore-not-found
oc delete resourceclaim nemotron3-super-pd-prefill-shared-channel --ignore-not-found
oc delete computedomain nemotron3-super-pd-compute-domain --ignore-not-found
oc apply -f pd/gb200-nemotron3-super-bf16-pd-resources.yaml
```

Then render the live ComputeDomain UID into the workload manifest and apply it:

```bash
NEMOTRON_DOMAIN_UID=$(oc get computedomain nemotron3-super-pd-compute-domain \
  -o jsonpath='{.metadata.uid}')

sed "s/REPLACE_WITH_COMPUTE_DOMAIN_UID/${NEMOTRON_DOMAIN_UID}/g" \
  pd/gb200-nemotron3-super-bf16-pd-tp2-tp4.yaml | oc apply -f -
```

Do not apply the workload file without replacing the placeholder, and regenerate
the named claim whenever the ComputeDomain is recreated.

## Nemotron TP4 decode startup OOM

`NVIDIA-Nemotron-3-Super-120B-A12B-BF16` hit a repeatable startup OOM on the
TP4 decode Pod with vLLM `0.24.0+rhaiv.13`, NIXL, the CuMem allocator, hybrid
Mamba KV cache, and CUDA graphs enabled. The failure occurs while
`initialize_kv_cache_tensors()` allocates the KV-cache tensors, after model
loading and memory profiling have completed.

Lowering `--gpu-memory-utilization` from `0.85` to `0.75` did not change the
failure mechanism:

| Setting | Final allocation | Free memory | CUDA Graph private pools |
| --- | ---: | ---: | ---: |
| `0.85` | 17.79 GiB | 8.58 GiB | 54.14 GiB |
| `0.75` | 15.49 GiB | 6.70 GiB | 54.15 GiB |

At `0.75`, vLLM reported 64.38 GiB used to load the model and then estimated
123.92 GiB as available for KV cache. Those values already exceed the
184.30 GiB physical capacity before other runtime allocations are included.
The eventual OOM had less than 0.5 GiB reserved-but-unallocated, so the evidence
points to cache memory overestimation/accounting rather than ordinary allocator
fragmentation. The precise root cause has not yet been confirmed upstream.

The current mitigation order is:

1. Add `--enforce-eager` and remove `--max-cudagraph-capture-size 128`. Confirm
   the engine configuration reports `enforce_eager=True`.
2. If automatic sizing still fails, use `--kv-cache-memory-bytes` to set an
   explicit per-GPU cache budget. This overrides `--gpu-memory-utilization`.
   A conservative starting point is `64G` for TP4 decode; TP2 prefill needs a
   smaller value because its per-GPU weight shard is larger.
3. Treat those explicit sizes as bring-up values and tune them independently
   for prefill and decode after the deployment is stable.

Related upstream material:

- [vLLM 0.24 cache configuration](https://docs.vllm.ai/en/v0.24.0/api/vllm/config/cache/)
  documents explicit `kv_cache_memory_bytes` sizing and its precedence over
  `gpu_memory_utilization`.
- [NIXL connector usage](https://github.com/vllm-project/vllm/blob/main/docs/features/nixl_connector_usage.md)
  documents the CuMem requirement for GB-series MNNVL and uses eager execution
  in its basic producer/consumer examples.
- [vLLM issue #40256](https://github.com/vllm-project/vllm/issues/40256)
  describes an analogous incorrect KV-cache estimate and startup OOM when a
  custom CUDA allocator participates in memory accounting.
- [vLLM issue #41830](https://github.com/vllm-project/vllm/issues/41830)
  covers startup OOMs involving KV transfer and the hybrid cache manager for
  Mamba/hybrid models. This deployment explicitly keeps the hybrid manager
  enabled, so it is related context rather than an exact reproduction.
- [vLLM issue #50714](https://github.com/vllm-project/vllm/issues/50714)
  tracks a separate NIXL interaction with packed hybrid KV caches and differing
  logical and physical block sizes.
