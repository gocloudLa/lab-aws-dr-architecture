#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need aws; need jq
operation=${1:?Uso: scripts/start-arc.sh switchover|failover TARGET_REGION}
target=${2:?Uso: scripts/start-arc.sh switchover|failover TARGET_REGION}
require_region "$target"
behavior=$(output_value arc_aurora_behavior)
case "$operation" in
  switchover)
    [[ "$behavior" == "switchoverOnly" ]] || { echo "El plan aplicado usa $behavior; aplique arc_aurora_behavior=switchoverOnly antes del ensayo" >&2; exit 65; }
    ;;
  failover)
    [[ "$behavior" == "failover" ]] || { echo "El plan aplicado usa $behavior; aplique arc_aurora_behavior=failover antes del ensayo" >&2; exit 65; }
    [[ "${ACCEPT_DATA_LOSS:-}" == "yes" ]] || { echo "Failover puede perder datos. Defina ACCEPT_DATA_LOSS=yes de forma explícita." >&2; exit 64; }
    ;;
  *) echo "Operación inválida: use switchover o failover" >&2; exit 64 ;;
esac
plan_arn=$(output_value arc_plan_arn)

request=$(temp_json); trap 'rm -f "$request"' EXIT
jq -n --arg plan "$plan_arn" --arg target "$target" --arg comment "Demo $operation iniciada por operador" \
  '{planArn:$plan,targetRegion:$target,action:"activate",mode:"graceful",latestVersion:"true",comment:$comment}' >"$request"
aws arc-region-switch start-plan-execution --region "$target" --cli-input-json "file://$request" --output json
echo "Ejecución iniciada siempre en modo graceful; conserve executionId para poll-arc.sh."
