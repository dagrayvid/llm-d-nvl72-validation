# DeepSeek-V4-Flash P/D benchmarks

Benchmark results for `RedHatAI/DeepSeek-V4-Flash-NVFP4-FP8` on GB200 NVL72.
Each model-server Pod uses tensor parallelism across four GPUs (`TP=4`).

## GuideLLM

| Results directory | Workload | P/D topology |
| --- | --- | --- |
| `deepseek-v4-flash-1000-1000/` | 1,000 input tokens / 1,000 output tokens | 1 prefill Pod / 2 decode Pods (`1P/2D`) |
| `deepseek-v4-flash-8000-1000/` | 8,000 input tokens / 1,000 output tokens | 2 prefill Pods / 1 decode Pod (`2P/1D`) |

The raw `benchmarks.json` exports are intentionally ignored by Git. The CSV
summaries and collected server logs are retained in the corresponding results
directories.

## AgentX

These runs used two prefill Pods and one decode Pod (`2P/1D`) and the
`semianalysisai/cc-traces-weka-062126` dataset with subagents.

| Results directory | Concurrency | Submission status |
| --- | ---: | --- |
| `2ptp4-1dtp4-agentx-c8-smoke/` | 8 | Invalid smoke test (`unsafe_override`) |
| `2ptp4-1dtp4-agentx-c16/` | 16 | Valid |
| `2ptp4-1dtp4-agentx-c32/` | 32 | Valid |
