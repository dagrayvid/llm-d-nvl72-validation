#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-dagray-dev}"
URL="${URL:-http://openshift-ai-inference-openshift-default.openshift-ingress.svc.cluster.local/dagray-dev/deepseek-v4-flash-pd}"
MODEL="${MODEL:-RedHatAI/DeepSeek-V4-Flash-NVFP4-FP8}"
TOKENIZER="${TOKENIZER:-${MODEL}}"
DEPLOYMENT="aiperf-agentx"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") ACTION [ARGUMENTS]

Actions:
  deploy                         Deploy the AgentX runner
  check                          Query /v1/models through the runner
  smoke [concurrency] [seconds]  Run an invalid short test (defaults: 8 60)
  run [concurrency] [seconds]    Run the benchmark (defaults: 8 900)
  results [directory]            Copy artifacts locally

Environment overrides:
  NAMESPACE, URL, MODEL, TOKENIZER
EOF
}

require_runner() {
  oc get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" >/dev/null
}

action="${1:-}"
case "${action}" in
  deploy)
    oc apply -n "${NAMESPACE}" -f "${SCRIPT_DIR}/agentx.yaml"
    oc rollout status -n "${NAMESPACE}" "deployment/${DEPLOYMENT}" --timeout=300s
    ;;

  check)
    require_runner
    oc exec -n "${NAMESPACE}" "deployment/${DEPLOYMENT}" -- \
      python -c "import urllib.request as u; print(u.urlopen('${URL}/v1/models', timeout=10).read().decode())"
    ;;

  smoke)
    require_runner
    concurrency="${2:-8}"
    duration="${3:-60}"
    oc exec -n "${NAMESPACE}" "deployment/${DEPLOYMENT}" -- \
      aiperf profile \
        --scenario inferencex-agentx-mvp \
        --unsafe-override \
        --url "${URL}" \
        --model "${MODEL}" \
        --tokenizer "${TOKENIZER}" \
        --tokenizer-trust-remote-code \
        --max-context-length 256000 \
        --endpoint-type chat \
        --streaming \
        --use-server-token-count \
        --public-dataset semianalysis_cc_traces_weka_with_subagents \
        --concurrency "${concurrency}" \
        --benchmark-duration "${duration}" \
        --output-artifact-dir /workspace/artifacts \
        --no-server-metrics \
        --ui simple
    ;;

  run)
    require_runner
    concurrency="${2:-8}"
    duration="${3:-900}"
    oc exec -n "${NAMESPACE}" "deployment/${DEPLOYMENT}" -- \
      aiperf profile \
        --scenario inferencex-agentx-mvp \
        --url "${URL}" \
        --model "${MODEL}" \
        --max-context-length 256000 \
        --endpoint-type chat \
        --streaming \
        --use-server-token-count \
        --public-dataset semianalysis_cc_traces_weka_with_subagents \
        --concurrency "${concurrency}" \
        --benchmark-duration "${duration}" \
        --output-artifact-dir /workspace/artifacts \
        --no-server-metrics \
        --ui simple
    ;;

  results)
    require_runner
    destination="${2:-./results/agentx}"
    mkdir -p "${destination}"
    pod="$(oc get pod -n "${NAMESPACE}" -l "app=${DEPLOYMENT}" -o jsonpath='{.items[0].metadata.name}')"
    oc cp "${NAMESPACE}/${pod}:/workspace/artifacts" "${destination}"
    ;;

  -h|--help|help)
    usage
    ;;

  *)
    usage >&2
    exit 2
    ;;
esac
