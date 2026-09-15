#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need aws; need jq
operation=${1:?Uso: scripts/poll-arc.sh switchover|failover EXECUTION_ID}
execution_id=${2:?Uso: scripts/poll-arc.sh switchover|failover EXECUTION_ID}
[[ "$execution_id" =~ ^(us-east-1|us-east-2)/[0-9A-Fa-f]{16}$ ]] || { echo "EXECUTION_ID inválido" >&2; exit 64; }
case "$operation" in switchover|failover) plan_arn=$(output_value arc_plan_arn);; *) exit 64;; esac
execution_region=${execution_id%%/*}
require_region "$execution_region"
timeout_seconds=${POLL_TIMEOUT_SECONDS:-3600}
[[ "$timeout_seconds" =~ ^[0-9]+$ ]] && (( timeout_seconds >= 10 )) || { echo "POLL_TIMEOUT_SECONDS debe ser un entero >= 10" >&2; exit 64; }
deadline=$((SECONDS + timeout_seconds))

while :; do
  result=$(aws arc-region-switch get-plan-execution --region "$execution_region" --plan-arn "$plan_arn" --execution-id "$execution_id" --output json)
  jq '{executionId,executionState,mode,updatedAt,steps:[.stepStates[]|{name,status,startTime,endTime}]}' <<<"$result"
  state=$(jq -r .executionState <<<"$result")
  case "$state" in completed) exit 0;; completedWithExceptions) echo "ARC completó con excepciones" >&2; exit 3;; failed|canceled|planExecutionTimedOut|pausedByFailedStep|pausedByOperator|pendingManualApproval) exit 2;; esac
  (( SECONDS < deadline )) || { echo "Timeout local de polling tras ${timeout_seconds}s; la ejecución ARC puede continuar" >&2; exit 124; }
  sleep 10
done
