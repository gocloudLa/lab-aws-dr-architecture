#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
AWS_PAGER=""
export AWS_PAGER

# Dos backends de orquestación conviven mientras se valida la migración:
#   terragrunt (default): un state por capa bajo terragrunt/<layer>/<project>/laboratory
#   terraform:            el root module único de terraform/examples/lab
# Exportar IAC_MODE=terraform para operar la demo contra el stack viejo.
IAC_MODE=${IAC_MODE:-terragrunt}
TG_ROOT=${TG_ROOT:-"$REPO_ROOT/terragrunt"}
TF_DIR=${TF_DIR:-"$REPO_ROOT/terraform/examples/lab"}

need() { command -v "$1" >/dev/null || { echo "Falta la herramienta requerida: $1" >&2; exit 69; }; }

# us-east-2 -> us_east_2. Clave normalizada de los mapas por región.
region_key() { printf '%s' "$1" | tr '-' '_'; }

# us-east-2 -> use2. Sufijo corto de la Standard Platform, usado en los nombres de capa.
region_short() {
  case "$1" in
    us-east-2) printf 'use2' ;;
    us-east-1) printf 'use1' ;;
    *) echo "Región fuera de la demo: $1" >&2; return 64 ;;
  esac
}

require_region() { case "$1" in us-east-2|us-east-1) ;; *) echo "Región fuera de la demo: $1" >&2; exit 64;; esac; }
temp_json() { mktemp "${TMPDIR:-/tmp}/aurora-dr.XXXXXX.json"; }

tg_layer_outputs() {
  local layer=$1 dir="$TG_ROOT/$1"
  [[ -d "$dir" ]] || { echo "No existe la capa Terragrunt: $layer" >&2; return 65; }
  (cd "$dir" && terragrunt output -json --non-interactive 2>/dev/null) || {
    echo "No se pudieron leer los outputs de la capa $layer; ¿ya se aplicó?" >&2
    return 65
  }
}

# Reconstruye el contrato de outputs que consumen los scripts a partir de las capas.
# Los nombres se mantienen idénticos a los del stack Terraform para no duplicar lógica.
tg_aggregate_outputs() {
  local global proj2 proj1 wl2 wl1 arc
  global=$(tg_layer_outputs project/drarch-global/laboratory)
  proj2=$(tg_layer_outputs project/drarch-use2/laboratory)
  proj1=$(tg_layer_outputs project/drarch-use1/laboratory)
  wl2=$(tg_layer_outputs workload/drarch-use2/laboratory)
  wl1=$(tg_layer_outputs workload/drarch-use1/laboratory)
  arc=$(tg_layer_outputs workload/drarch-arc/laboratory)

  jq -n \
    --argjson global "$global" \
    --argjson proj2 "$proj2" \
    --argjson proj1 "$proj1" \
    --argjson wl2 "$wl2" \
    --argjson wl1 "$wl1" \
    --argjson arc "$arc" \
    '
    def v(x): { value: x };
    {
      app_dns_name:              v($arc.app_dns_name.value),
      arc_plan_arn:              v($arc.arc_plan_arn.value),
      arc_aurora_behavior:       v($arc.arc_aurora_behavior.value),
      region_roles:              v($arc.region_roles.value),
      public_zone_id:            v($arc.public_zone_id.value),

      global_cluster_identifier: v($global.global_cluster_identifier.value),
      global_writer_endpoint:    v($global.global_writer_endpoint.value),
      aurora_engine_version:     v($global.aurora_engine_version.value),

      aurora_instance_class:     v($proj2.aurora_instance_class.value),

      ecr_repository_urls: v({
        us_east_2: $proj2.ecr_repository_url.value,
        us_east_1: $proj1.ecr_repository_url.value
      }),
      regional_app_urls: v({
        us_east_2: $wl2.regional_app_url.value,
        us_east_1: $wl1.regional_app_url.value
      }),
      ecs_cluster_names: v({
        us_east_2: $wl2.ecs_cluster_name.value,
        us_east_1: $wl1.ecs_cluster_name.value
      }),
      ecs_service_names: v({
        us_east_2: $wl2.ecs_service_name.value,
        us_east_1: $wl1.ecs_service_name.value
      }),
      aurora_cluster_arns: v({
        us_east_2: $proj2.aurora_cluster_arn.value,
        us_east_1: $proj1.aurora_cluster_arn.value
      }),
      aurora_cluster_endpoints: v({
        us_east_2: $proj2.aurora_cluster_endpoint.value,
        us_east_1: $proj1.aurora_cluster_endpoint.value
      })
    }'
}

# Los outputs se leen una sola vez por invocación: con Terragrunt son seis llamadas.
_OUTPUTS_CACHE=""
tf_outputs() {
  if [[ -z "$_OUTPUTS_CACHE" ]]; then
    case "$IAC_MODE" in
      terragrunt) need terragrunt; need jq; _OUTPUTS_CACHE=$(tg_aggregate_outputs) ;;
      terraform)  need terraform; _OUTPUTS_CACHE=$(terraform -chdir="$TF_DIR" output -json) ;;
      *) echo "IAC_MODE inválido: $IAC_MODE (terragrunt|terraform)" >&2; exit 64 ;;
    esac
  fi
  printf '%s' "$_OUTPUTS_CACHE"
}

output_value() {
  local name=$1
  tf_outputs | jq -er --arg name "$name" '.[$name].value'
}

map_value() {
  local output=$1 key=$2
  key=$(region_key "$key")
  output_value "$output" | jq -er --arg key "$key" '.[$key]'
}
