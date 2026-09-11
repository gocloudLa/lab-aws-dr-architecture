#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
stub_dir=$(mktemp -d "${TMPDIR:-/tmp}/aurora-dr-contracts.XXXXXX")
trap 'rm -rf "$stub_dir"' EXIT

# lib.sh agrega los outputs corriendo `terragrunt output -json` una vez por capa. El stub
# devuelve, en cada llamada, un superset con todas las claves que las capas aportan; la
# agregación de lib.sh toma de cada una sólo las que le corresponden. Alcanza para que
# start-arc/poll-arc resuelvan arc_plan_arn y arc_aurora_behavior.
cat >"$stub_dir/terragrunt" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"arc_plan_arn":{"value":"arn:aws:arc-region-switch:us-east-2:123456789012:plan/example"},"arc_aurora_behavior":{"value":"switchoverOnly"},"app_dns_name":{"value":"app.example.com"},"region_roles":{"value":{}},"public_zone_id":{"value":"Z0"},"global_cluster_identifier":{"value":"mock-global"},"global_writer_endpoint":{"value":"mock.endpoint"},"aurora_engine_version":{"value":"16.14"},"aurora_instance_class":{"value":"db.r6g.large"},"ecr_repository_url":{"value":"mock"},"regional_app_url":{"value":"https://mock"},"ecs_cluster_name":{"value":"mock"},"ecs_service_name":{"value":"mock"},"aurora_cluster_arn":{"value":"arn:mock"},"aurora_cluster_endpoint":{"value":"mock"}}
JSON
EOF

cat >"$stub_dir/aws" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" get-plan "* ]]; then
  # start-arc.sh resuelve la versión del plan antes de ejecutarlo: el servicio espera
  # ese número en latestVersion (no un booleano).
  printf '1\n'
elif [[ " $* " == *" start-plan-execution "* ]]; then
  input=""
  while (($#)); do
    if [[ "$1" == "--cli-input-json" ]]; then
      input=${2#file://}
      break
    fi
    shift
  done
  [[ -n "$input" ]] || { echo "Falta --cli-input-json" >&2; exit 64; }
  cp "$input" "$AWS_CAPTURE"
  printf '{"executionId":"us-east-1/0123456789abcdef"}\n'
else
  jq -n --arg state "${FAKE_ARC_STATE:-completed}" '{executionId:"us-east-1/0123456789abcdef",executionState:$state,mode:"graceful",stepStates:[]}'
fi
EOF
chmod +x "$stub_dir/terragrunt" "$stub_dir/aws"

capture="$stub_dir/request.json"

PATH="$stub_dir:$PATH" AWS_CAPTURE="$capture" "$repo_root/scripts/start-arc.sh" switchover us-east-1 >/dev/null
jq -e '.targetRegion == "us-east-1" and .action == "activate" and .mode == "graceful" and .latestVersion == "1"' "$capture" >/dev/null

if PATH="$stub_dir:$PATH" AWS_CAPTURE="$capture" FAKE_ARC_STATE=completedWithExceptions \
  "$repo_root/scripts/poll-arc.sh" switchover us-east-1/0123456789abcdef >/dev/null 2>&1; then
  echo "poll-arc aceptó completedWithExceptions" >&2
  exit 1
else
  status=$?
  [[ "$status" -eq 3 ]] || { echo "poll-arc devolvió $status, se esperaba 3" >&2; exit 1; }
fi

PATH="$stub_dir:$PATH" AWS_CAPTURE="$capture" FAKE_ARC_STATE=completed \
  "$repo_root/scripts/poll-arc.sh" switchover us-east-1/0123456789abcdef >/dev/null

echo "Contratos locales start-arc/poll-arc: OK"
