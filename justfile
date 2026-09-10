namespace := env_var_or_default("NAMESPACE", "dagray-dev")
url := env_var_or_default("URL", "http://openshift-ai-inference-openshift-default.openshift-ingress.svc.cluster.local/dagray-dev/deepseek-v4-flash-pd")
model := env_var_or_default("MODEL", "RedHatAI/DeepSeek-V4-Flash-NVFP4-FP8")
tokenizer := env_var_or_default("TOKENIZER", model)
guidellm_deploy := "guidellm"
agentx_deploy := "aiperf-agentx"

default:
    @just --list

guidellm-deploy:
    oc apply -n {{namespace}} -f benchmarks/guidellm.yaml
    oc rollout status -n {{namespace}} deployment/{{guidellm_deploy}} --timeout=300s

guidellm-check:
    oc exec -n {{namespace}} deployment/{{guidellm_deploy}} -- \
      python -c "import urllib.request as u; print(u.urlopen('{{url}}/v1/models', timeout=10).read().decode())"

guidellm-8k1k streams='[1,2,4,8]' duration="120":
    oc exec -n {{namespace}} deployment/{{guidellm_deploy}} -- \
      env LLMISVC_URL={{url}} PROMPT_TOKENS=8000 OUTPUT_TOKENS=1000 \
      GUIDELLM_PROFILE='{"kind":"concurrent","streams":{{streams}}}' \
      BENCHMARK_DURATION={{duration}} /scripts/run.sh

guidellm-1k1k streams='[1,2,4,8]' duration="120":
    oc exec -n {{namespace}} deployment/{{guidellm_deploy}} -- \
      env LLMISVC_URL={{url}} PROMPT_TOKENS=1000 OUTPUT_TOKENS=1000 \
      GUIDELLM_PROFILE='{"kind":"concurrent","streams":{{streams}}}' \
      BENCHMARK_DURATION={{duration}} /scripts/run.sh

guidellm-results dest="./results/guidellm":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{dest}}"
    pod="$(oc get pod -n {{namespace}} -l app={{guidellm_deploy}} -o jsonpath='{.items[0].metadata.name}')"
    oc cp "{{namespace}}/${pod}:/results/output" "{{dest}}"

agentx-deploy:
    oc apply -n {{namespace}} -f benchmarks/agentx.yaml
    oc rollout status -n {{namespace}} deployment/{{agentx_deploy}} --timeout=300s

agentx-check:
    oc exec -n {{namespace}} deployment/{{agentx_deploy}} -- \
      python -c "import urllib.request as u; print(u.urlopen('{{url}}/v1/models', timeout=10).read().decode())"

agentx-smoke concurrency="8" duration="60":
    oc exec -n {{namespace}} deployment/{{agentx_deploy}} -- \
      aiperf profile \
        --scenario inferencex-agentx-mvp \
        --unsafe-override \
        --url {{url}} \
        --model {{model}} \
        --tokenizer {{tokenizer}} \
        --tokenizer-trust-remote-code \
        --max-context-length 256000 \
        --endpoint-type chat \
        --streaming \
        --use-server-token-count \
        --public-dataset semianalysis_cc_traces_weka_with_subagents \
        --concurrency {{concurrency}} \
        --benchmark-duration {{duration}} \
        --output-artifact-dir /workspace/artifacts \
        --no-server-metrics \
        --ui simple

agentx-run concurrency="8" duration="900":
    oc exec -n {{namespace}} deployment/{{agentx_deploy}} -- \
      aiperf profile \
        --scenario inferencex-agentx-mvp \
        --url {{url}} \
        --model {{model}} \
        --max-context-length 256000 \
        --endpoint-type chat \
        --streaming \
        --use-server-token-count \
        --public-dataset semianalysis_cc_traces_weka_with_subagents \
        --concurrency {{concurrency}} \
        --benchmark-duration {{duration}} \
        --output-artifact-dir /workspace/artifacts \
        --no-server-metrics \
        --ui simple

agentx-results dest="./results/agentx":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{dest}}"
    pod="$(oc get pod -n {{namespace}} -l app={{agentx_deploy}} -o jsonpath='{.items[0].metadata.name}')"
    oc cp "{{namespace}}/${pod}:/workspace/artifacts" "{{dest}}"
