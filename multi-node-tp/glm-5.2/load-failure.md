# GLM-5.2 multi-node TP=8 load failure

## Summary

On 2026-09-10, vLLM failed under concurrent inference load while serving
`RedHatAI/GLM-5.2-NVFP4` with TP=8 across two GB200 nodes. The initial failure
occurred at concurrency 100 and was reproduced at concurrency 8. Concurrency 1
and 2 completed without a fatal engine failure.

The engine stopped because a tensor-parallel worker did not respond before the
distributed RPC timeout:

```text
File "vllm/v1/executor/multiproc_executor.py", line 387, in get_response
    status, result = mq.dequeue(timeout=dequeue_timeout)
File "vllm/distributed/device_communicators/shm_broadcast.py", line 698, in acquire_read
    self._spin_condition.wait(timeout_ms=read_timeout.timeout_ms())
File "vllm/distributed/device_communicators/shm_broadcast.py", line 647, in timeout_ms
    raise TimeoutError
TimeoutError

The above exception was the direct cause of the following exception:

File "vllm/v1/executor/multiproc_executor.py", line 389, in get_response
    raise TimeoutError(f"RPC call to {method} timed out.") from e
TimeoutError: RPC call to sample_tokens timed out.
```

## Deployment

- vLLM `0.24.0+rhaiv.13`
- Two GB200 nodes with four GPUs per node
- TP=8 using vLLM multi-node multiprocessing
- NVIDIA ComputeDomain/DRA with MNNVL
- `NCCL_MNNVL_ENABLE=1` and `NCCL_CUMEM_ENABLE=1`
- GuideLLM requests with 8,000 input and 1,000 output tokens

## Reproduction results

| Concurrency | Completed | Incomplete | Errors | Fatal engine failure |
| ---: | ---: | ---: | ---: | :---: |
| 1 | 14 | 0 | 0 | No |
| 2 | 25 | 1 | 0 | No |
| 8 | 40 | 0 | 8 | Yes |

At the failing step:

- Eight requests were running and none were waiting.
- The scheduler filled its 8,192-token budget with mixed prefill and decode work.
- GPU KV-cache usage was only 5.4%.
- Prefix-cache counters were all zero.
- No OOM or explicit CUDA error appeared in the supplied leader log.

## Assessment

This is a load-dependent distributed worker stall, not KV-cache exhaustion. The
`sample_tokens` timeout is the visible consequence; it does not identify the
stalled rank or prove where that rank became stuck.

The leading hypothesis is a problem in the multi-node MNNVL/NCCL or associated
model-execution path. A successful TP=8 test on eight B200 GPUs in one x86 node
does not cover this path. Worker logs, NCCL diagnostics, and node kernel logs are
still required to determine the root cause.

## Related upstream issues

- [vLLM #48752: GLM-5.2 TP=8 across two GB200 nodes—`sample_tokens` timeout](https://github.com/vllm-project/vllm/issues/48752) closely matches the hardware topology and failure signature, but that report used DSpark speculative decoding while this deployment has `speculative_config=None`.
- [vLLM #40926: GLM workers hang under sustained traffic—`sample_tokens` timeout](https://github.com/vllm-project/vllm/issues/40926) describes the same worker-stall signature, including a later reproduction without speculative decoding. Its configuration includes GLM-5.1 and LMCache, which are not used here.

These establish a related failure pattern but are not confirmed as the same root
cause.

## Next steps

1. Capture timestamped logs from both vLLM pods around the start of the stall.
2. Enable NCCL and PyTorch collective timeout/desynchronization diagnostics.
3. Check both nodes for NVIDIA Xid, NVLink, OOM, watchdog, or reset messages.
4. Test concurrency 4 and 6 to narrow the failure threshold.
5. Capture per-GPU utilization, memory utilization, and power during the stall.
