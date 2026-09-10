#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need aws; need jq
action=${1:?Uso: scripts/app-fault.sh stop|restore REGION}
region=${2:?Uso: scripts/app-fault.sh stop|restore REGION}
require_region "$region"
cluster=$(map_value ecs_cluster_names "$region"); service=$(map_value ecs_service_names "$region")
state_file=${FAULT_STATE_FILE:-"${TMPDIR:-/tmp}/aurora-dr-fault-${region}.json"}
case "$action" in
  stop)
    desired=$(aws ecs describe-services --region "$region" --cluster "$cluster" --services "$service" --output json | jq -er '.services[0].desiredCount')
    [[ "$desired" -gt 0 ]] || { echo "El servicio ya tiene desiredCount=0 en $region" >&2; exit 65; }
    jq -n --arg region "$region" --arg cluster "$cluster" --arg service "$service" --argjson desired "$desired" \
      '{region:$region,cluster:$cluster,service:$service,desiredCount:$desired}' >"$state_file"
    aws ecs update-service --region "$region" --cluster "$cluster" --service "$service" --desired-count 0 --output json | jq '{service:.service.serviceName,desired:.service.desiredCount}'
    echo "Falla reversible de capa web; estado guardado en $state_file"
    ;;
  restore)
    [[ -f "$state_file" ]] || { echo "No existe estado de restauración: $state_file" >&2; exit 66; }
    for execution_region in us-east-2 us-east-1; do
      active=$(aws arc-region-switch list-plan-executions --region "$execution_region" --plan-arn "$(output_value arc_plan_arn)" --max-results 20 --output json | jq '[.items[]? | select(.executionState == "inProgress" or .executionState == "pending")] | length')
      [[ "$active" -eq 0 ]] || { echo "Se rechaza restore: hay una ejecución ARC activa en $execution_region" >&2; exit 65; }
    done
    desired=$(jq -er .desiredCount "$state_file")
    aws ecs update-service --region "$region" --cluster "$cluster" --service "$service" --desired-count "$desired" --output json | jq '{service:.service.serviceName,desired:.service.desiredCount}'
    echo "Servicio restaurado como warm standby; el Global Writer Endpoint resuelve el writer actual."
    ;;
  *) exit 64;;
esac
