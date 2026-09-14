# AgentX: WideEP versus PD

This compares the experimental AgentX results for the following three-node
DeepSeek-V4-Flash deployments:

- PD: two TP4 prefill Pods and one TP4 decode Pod (`2ptp4-1dtp4`)
- WideEP: one DP8/EP8 prefill group spanning two Pods and one DP4/EP4 decode
  Pod (`2pdp8-1ddp4`)

Both used the same model, AgentX scenario, requested concurrency, and a
900-second profiling duration.

## Results

| Concurrency | Metric | PD | WideEP | WideEP change |
|---:|---|---:|---:|---:|
| 16 | Request throughput | 0.354 req/s | 0.274 req/s | -22% |
| 16 | Output throughput | 212 tok/s | 149 tok/s | -30% |
| 16 | Average TTFT | 793 ms | 1,368 ms | +72% |
| 16 | Average ITL | 6.71 ms | 9.75 ms | +45% |
| 16 | Average request latency | 4.90 s | 6.74 s | +38% |
| 32 | Request throughput | 0.589 req/s | 0.687 req/s | +17% |
| 32 | Output throughput | 450 tok/s | 557 tok/s | +24% |
| 32 | Average TTFT | 2,266 ms | 1,918 ms | -15% |
| 32 | Average ITL | 7.63 ms | 10.91 ms | +43% |
| 32 | Average request latency | 8.13 s | 10.83 s | +33% |

At concurrency 32, WideEP sustained higher effective concurrency: 7.44
requests versus 4.79 for PD. This produced higher aggregate request and output
throughput, but individual requests were slower:

- Per-user output throughput was 35% lower.
- End-to-end per-user output throughput was 26% lower.
- Average decode duration was 52% higher.
- P99 request latency was 98.8 seconds, versus 51.1 seconds for PD.

## Interpretation

The current results suggest that PD provides better latency and decode
efficiency. WideEP can sustain more concurrent work and provide better
aggregate throughput at concurrency 32, but with a substantial per-request
latency penalty. At concurrency 16, WideEP did not provide an aggregate
capacity advantage.

## Comparison caveat

These were not paired trials: AIPerf selected a different random seed and
trajectory mix for each run. At concurrency 32, the WideEP run had 10.6%
shorter input sequences and 6% longer output sequences on average. This makes
the aggregate-throughput comparison directional rather than conclusive.

A stronger comparison should repeat both deployments with an identical fixed
random seed, ideally across multiple trials.

## Source artifacts

- `../pd/2ptp4-1dtp4-agentx-c16/profile_export_aiperf.json`
- `../pd/2ptp4-1dtp4-agentx-c32/profile_export_aiperf.json`
- `2pdp8-1ddp4-agentx-c16/profile_export_aiperf.json`
- `2pdp8-1ddp4-agentx-c32/profile_export_aiperf.json`
