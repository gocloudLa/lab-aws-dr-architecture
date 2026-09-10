#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
for tool in aws terraform jq curl; do need "$tool"; done

aws sts get-caller-identity --output json | jq '{Account,Arn}'
outputs=$(tf_outputs)
for name in ecr_repository_urls ecs_cluster_names ecs_service_names regional_app_urls app_dns_name arc_plan_arn arc_aurora_behavior global_cluster_identifier global_writer_endpoint aurora_engine_version aurora_min_acu aurora_max_acu; do
  jq -e --arg name "$name" '.[$name].value != null' <<<"$outputs" >/dev/null || { echo "Falta output Terraform: $name" >&2; exit 65; }
done

for region in us-east-2 us-east-1; do
  key=$(region_key "$region")
  engine_version=$(jq -r '.aurora_engine_version.value' <<<"$outputs")
  aws rds describe-db-engine-versions --region "$region" --engine aurora-postgresql --engine-version "$engine_version" --output json \
    | jq -e --arg version "$engine_version" '.DBEngineVersions | any(.EngineVersion == $version and .SupportsGlobalDatabases == true)' >/dev/null
  aws rds describe-orderable-db-instance-options --region "$region" --engine aurora-postgresql --engine-version "$engine_version" \
    --db-instance-class db.serverless --output json | jq -e '.OrderableDBInstanceOptions | length > 0' >/dev/null
  cluster=$(jq -r --arg r "$key" '.ecs_cluster_names.value[$r]' <<<"$outputs")
  service=$(jq -r --arg r "$key" '.ecs_service_names.value[$r]' <<<"$outputs")
  aws ecs describe-clusters --region "$region" --clusters "$cluster" --output json \
    | jq -e '.failures | length == 0' >/dev/null
  aws ecs describe-services --region "$region" --cluster "$cluster" --services "$service" --output json \
    | jq -e '.failures | length == 0 and (.services | length) == 1 and .services[0].desiredCount > 0 and .services[0].runningCount >= .services[0].desiredCount' >/dev/null \
    || { echo "ECS no está warm y estable en $region" >&2; exit 70; }
  regional_url=$(jq -r --arg r "$key" '.regional_app_urls.value[$r]' <<<"$outputs")
  expected_issuer="https://$(jq -r '.app_dns_name.value' <<<"$outputs")/realms/${DEMO_REALM:-community-day}"
  curl --fail --silent --show-error "$regional_url/realms/${DEMO_REALM:-community-day}/.well-known/openid-configuration" \
    | jq -e --arg issuer "$expected_issuer" '.issuer == $issuer' >/dev/null \
    || { echo "OIDC regional no está listo en $region" >&2; exit 70; }
done
min_acu=$(jq -r '.aurora_min_acu.value' <<<"$outputs"); max_acu=$(jq -r '.aurora_max_acu.value' <<<"$outputs")
jq -en --argjson min "$min_acu" --argjson max "$max_acu" '$min > 0 and $max >= $min' >/dev/null || { echo "Rango ACU inválido" >&2; exit 65; }
if jq -en --argjson min "$min_acu" '$min < 8' >/dev/null; then echo "ADVERTENCIA: mínimo $min_acu ACU es perfil de laboratorio; no usar para prometer RTO." >&2; fi

plan_arn=$(jq -r '.arc_plan_arn.value' <<<"$outputs")
aws arc-region-switch get-plan-evaluation-status --region us-east-2 --plan-arn "$plan_arn" --output json \
  | jq -e '.evaluationState | ascii_downcase == "passed"' >/dev/null || { echo "La evaluación ARC no está en passed" >&2; exit 70; }
echo "Preflight completo: cuenta, regiones, ambos ECS warm, OIDC regional y evaluación ARC disponibles."
