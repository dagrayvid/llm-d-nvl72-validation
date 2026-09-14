# GB200 NVL72 cluster validation

This repository records end-to-end validation of a three-node GB200 NVL72
OpenShift cluster running Red Hat OpenShift AI 3.5 and llm-d. The core platform
is operational: models can be staged locally, GPUs and Multi-Node NVLink
(MNNVL) can be allocated through NVIDIA DRA, and llm-d serves models using
multi-node tensor parallelism, disaggregated prefill/decode, and WideEP.

The most important findings were not basic model-serving failures. They were
integration and lifecycle limitations around the GPU Operator, ComputeDomains,
and DRA `ResourceClaim`s. These are summarized below and documented alongside
the relevant manifests and results.

## Validation status

| Workstream | Status | Outcome |
| --- | --- | --- |
| Model storage | Validated | A node-local 1.5 TiB RWX model-cache PVC and downloader DaemonSet were used to stage models for Model Express/PVC-backed serving. See [`setup/model-cache/`](setup/model-cache/). |
| GPU Operator, DRA, and MNNVL | Validated with workarounds | ComputeDomains, DRA GPU allocation, IMEX channels, and multi-node `nvbandwidth` smoke tests worked. The GPU Operator setup problem has been raised with its maintainers; the multiple-Pod channel-claim behavior is also tracked in [NVIDIA DRA driver issue #309](https://github.com/kubernetes-sigs/dra-driver-nvidia-gpu/issues/309). Installation and test material is under [`setup/nvidia-dra-driver-verification/`](setup/nvidia-dra-driver-verification/) and its [IMEX tests](setup/nvidia-dra-driver-verification/imex-test-jobs/README.md). |
| Red Hat OpenShift AI 3.5 | Validated | RHOAI/llm-d installation, Gateway routing, and a small Qwen3 P/D smoke deployment were exercised. See [`setup/rhoai/`](setup/rhoai/). |
| Multi-node TP over MNNVL | Validated, with one model-specific runtime failure | DeepSeek-R1-0528 ran with TP8 across two nodes and produced benchmark artifacts. GLM-5.2 TP8 served at concurrency 1-4 but hit a distributed `sample_tokens` timeout under moderate load. See [`multi-node-tp/`](multi-node-tp/) and the [GLM failure analysis](multi-node-tp/glm-5.2/load-failure.md). |
| DeepSeek-V4-Flash P/D | Validated | TP4 prefill and decode deployments worked in both 1P/2D and 2P/1D arrangements. GuideLLM and experimental AgentX results are under [`pd/`](pd/) with details in the [P/D README](pd/README.md). |
| Nemotron-3 Super P/D | Functionally validated | `NVIDIA-Nemotron-3-Super-120B-A12B-BF16` runs as two TP2 prefill Pods and one TP4 decode Pod across two nodes. Successful NIXL transfers were observed. Bring-up required explicit KV-cache sizing, Triton MoE on the memory-constrained TP2 prefill Pods, and the shared named channel-claim workaround described by [NVIDIA DRA driver issue #309](https://github.com/kubernetes-sigs/dra-driver-nvidia-gpu/issues/309). See the [resource manifest](pd/gb200-nemotron3-super-bf16-pd-resources.yaml) and [workload manifest](pd/gb200-nemotron3-super-bf16-pd-tp2-tp4.yaml). |
| Qwen 3.6 | Pending | Qwen3-0.6B was used for the initial RHOAI smoke test, but Qwen 3.6 has not yet been captured as a completed model validation in this repository. |
| DeepSeek-V4-Flash WideEP | Validated | WideEP with MNNVL was exercised in 2P/1D and 1P/2D shapes using [RedHatAI/DeepSeek-V4-Flash-NVFP4-FP8](https://huggingface.co/RedHatAI/DeepSeek-V4-Flash-NVFP4-FP8). Manifests, GuideLLM results, and experimental AgentX results are under [`wide-ep/`](wide-ep/). See the [PD comparison](wide-ep/AGENTX_COMPARISON.md) and [compressed-results notes](wide-ep/COMPRESSED_RESULTS.md). |

## Principal findings and limitations

### GPU Operator and ComputeDomain setup required workarounds

The GPU Operator 26.7 ComputeDomain daemon lacked permission to delete
`ComputeDomainClique` resources while updating owner references on OpenShift.
It also required the appropriate SCC assignment. The supplemental RBAC/SCC
workaround is retained in
[`setup/gpu-operator/missing-scc-fix.yaml`](setup/gpu-operator/missing-scc-fix.yaml).
Without it, ComputeDomain setup could fail before any llm-d workload started.
This problem has been raised with the maintainers of the NVIDIA GPU Operator.

### Observed DRA limitation for multiple model Pods on one ComputeDomain node

This deployment did use `ResourceClaimTemplate`s: the llm-d Pod templates
referenced the GPU and ComputeDomain-generated channel templates through
`resourceClaimTemplateName`. That standard path creates a separate channel
claim for each replica. With the driver version installed in this cluster,
only the first independently generated channel claim could be allocated on a
node, so two TP2 prefill Pods could not share a four-GPU node even when two
GPUs remained available.

The working Nemotron topology manually creates one named, node-local
`ResourceClaim` and shares it between the two prefill Pods. That claim embeds
the live ComputeDomain UID, is immutable, and must be recreated whenever the
ComputeDomain is recreated.

This should be treated as an observed limitation of the deployed
ComputeDomain/DRA integration, not as a general claim that heterogeneous TP is
unsupported. [NVIDIA DRA driver issue #309](https://github.com/kubernetes-sigs/dra-driver-nvidia-gpu/issues/309)
explicitly describes multiple Pods on one ComputeDomain node as a valid MNNVL
use case and identifies a manually shared `ResourceClaim` as the current
workaround. vLLM/NIXL successfully transferred cache state between the TP2
prefill and TP4 decode engines. The full procedure and related upstream
references are in the [P/D README](pd/README.md).

### GLM-5.2 TP8 distributed worker timeout

`RedHatAI/GLM-5.2-NVFP4` partially worked with TP8 across two four-GPU GB200
nodes. It completed low-concurrency requests, but at concurrency 8 and above a
worker stalled until vLLM reported `RPC call to sample_tokens timed out`.
Graph compilation and warmup also took approximately 25 minutes. This was a
load-dependent distributed-runtime failure, not a model-load or KV-cache OOM.

The failure was observed with the RHAIIS vLLM 0.24.0+rhaiv.13 image and has
been raised with vLLM/RHAIIS engineering. [vLLM issue #48752](https://github.com/vllm-project/vllm/issues/48752)
has a closely related GLM-5.2, TP8, two-node GB200 signature, although its
configuration differs and the common root cause is not confirmed. The
[detailed failure analysis](multi-node-tp/glm-5.2/load-failure.md) preserves
the exact evidence and caveats.

### Manual GPU-memory sizing was needed for reliable startup

vLLM's default memory estimation did not leave reliable startup and warmup
headroom for every validated model/topology. This is manageable in a test
environment, but requiring model- and role-specific tuning is a production
usability concern.

The manifests record manual tuning for these models:

- `NVIDIA-Nemotron-3-Super-120B-A12B-BF16`: automatic KV-cache sizing failed
  during cache allocation even after lowering `--gpu-memory-utilization`. The
  working TP2/TP4 P/D deployment sets `--kv-cache-memory-bytes 64G` explicitly
  per GPU.
- `RedHatAI/DeepSeek-V4-Flash-NVFP4-FP8`: the validated P/D and WideEP
  manifests set `--gpu-memory-utilization` explicitly (`0.75`-`0.8`, depending
  on role/topology) to preserve memory for model initialization, compilation,
  and kernel warmup.

### Nemotron TP2 MoE weight conversion required a separate workaround

The Nemotron TP2 prefill Pods also exposed a CuMem/FlashInfer MoE
weight-conversion OOM while loading the model. Their working configuration
selects the Triton MoE backend while retaining CuMem for MNNVL. This is distinct
from both KV-cache sizing and the GLM distributed worker timeout; none of the
three failures demonstrates a failure of MNNVL itself.

## Repository guide

- [`setup/model-cache/`](setup/model-cache/) — model-cache PV/PVC, node setup,
  validation, and downloader DaemonSet.
- [`setup/gpu-operator/`](setup/gpu-operator/) — cluster-specific GPU Operator
  fixes and an IMEX smoke workload.
- [`setup/nvidia-dra-driver-verification/`](setup/nvidia-dra-driver-verification/README.md)
  — detailed NVIDIA DRA installation and verification instructions.
- [`setup/rhoai/`](setup/rhoai/) — RHOAI Gateway and initial P/D smoke manifests.
- [`multi-node-tp/`](multi-node-tp/) — TP8 MNNVL manifests, results, and failure
  evidence.
- [`pd/`](pd/README.md) — P/D manifests, benchmark results, DRA workaround, and
  Nemotron startup analysis.
- [`wide-ep/`](wide-ep/) — WideEP manifests and results, including the
  [WideEP-versus-P/D analysis](wide-ep/AGENTX_COMPARISON.md).
- [`benchmarks/`](benchmarks/) — reusable GuideLLM and AgentX runner
  Deployments.
- [`troubleshooting/`](troubleshooting/) — retained node-level diagnostic
  evidence.

## Maintainer benchmark workflow

The `justfile` defaults target the DeepSeek-V4-Flash P/D service in
`dagray-dev`. Override the target when validating another deployment:

```bash
export NAMESPACE=dagray-dev
export URL=http://openshift-ai-inference-openshift-default.openshift-ingress.svc.cluster.local/dagray-dev/deepseek-v4-flash-pd
export MODEL=RedHatAI/DeepSeek-V4-Flash-NVFP4-FP8
export TOKENIZER="$MODEL"
```

GuideLLM:

```bash
just guidellm-deploy
just guidellm-check
just guidellm-8k1k '[1,2,4,8]' 120
just guidellm-1k1k '[1,2,4,8]' 120
just guidellm-results
```

AgentX:

```bash
just agentx-deploy
just agentx-check
just agentx-smoke 8 60
just agentx-run 8 900
just agentx-results
```

The AgentX smoke command uses an unsafe duration override and is not a valid
submission. Normal AgentX runs retain the scenario's 900-second minimum.
GuideLLM results are stored on an `emptyDir`; copy them out before deleting the
runner Deployment.
