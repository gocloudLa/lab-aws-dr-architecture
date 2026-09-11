#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
stub_dir=$(mktemp -d "${TMPDIR:-/tmp}/aurora-dr-contracts.XXXXXX")
trap 'rm -rf "$stub_dir"' EXIT

cat >"$stub_dir/terraform" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"arc_plan_arn":{"value":"arn:aws:arc-region-switch:us-east-2:123456789012:plan/example"},"arc_aurora_behavior":{"value":"switchoverOnly"}}
JSON
EOF

cat >"$stub_dir/aws" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" start-plan-execution "* ]]; then
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
chmod +x "$stub_dir/terraform" "$stub_dir/aws"

capture="$stub_dir/request.json"

# El stub reemplaza el binario terraform, así que este test corre en IAC_MODE=terraform.
# Lo que valida es la lógica de start-arc/poll-arc, que es igual con las dos orquestaciones.
export IAC_MODE=terraform

PATH="$stub_dir:$PATH" AWS_CAPTURE="$capture" "$repo_root/scripts/start-arc.sh" switchover us-east-1 >/dev/null
jq -e '.targetRegion == "us-east-1" and .action == "activate" and .mode == "graceful" and .latestVersion == "true"' "$capture" >/dev/null

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
