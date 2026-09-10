# GB200 NVL72 validation

Deployment manifests, cluster setup notes, troubleshooting evidence, and
benchmark tooling for the GB200 NVL72 validation environment.

## Layout

- `setup/`: cluster, GPU Operator, DRA, storage, and RHOAI setup material.
- `multi-node-tp/`: multi-node tensor-parallel deployments and results.
- `pd/`: prefill/decode deployment manifests.
- `benchmarks/`: reusable GuideLLM and AgentX runner Deployments.
- `troubleshooting/`: node-level diagnostic evidence.

## Benchmark configuration

The `justfile` defaults target the DeepSeek-V4-Flash P/D service in
`dagray-dev`. Override any value from the environment:

```bash
export NAMESPACE=dagray-dev
export URL=http://openshift-ai-inference-openshift-default.openshift-ingress.svc.cluster.local/dagray-dev/deepseek-v4-flash-pd
export MODEL=RedHatAI/DeepSeek-V4-Flash-NVFP4-FP8
export TOKENIZER="$MODEL"
```

### GuideLLM

```bash
just guidellm-deploy
just guidellm-check
just guidellm-8k1k '[1,2,4,8]' 120
just guidellm-1k1k '[1,2,4,8]' 120
just guidellm-results
```

The two workloads use synthetic requests with 8,000 input/1,000 output tokens
and 1,000 input/1,000 output tokens respectively. Results live on an `emptyDir`;
copy them out before deleting the runner Deployment.

### AgentX

```bash
just agentx-deploy
just agentx-check
just agentx-smoke 8 60
just agentx-run 8 900
just agentx-results
```

The smoke run uses AgentX's unsafe duration override and is not a valid
submission. The normal run retains the scenario's 900-second minimum.
