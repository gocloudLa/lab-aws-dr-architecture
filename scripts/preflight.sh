#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
for tool in aws jq curl; do need "$tool"; done

aws sts get-caller-identity --output json | jq '{Account,Arn}'
outputs=$(tf_outputs)
for name in ecr_repository_urls ecs_cluster_names ecs_service_names regional_app_urls app_dns_name arc_plan_arn arc_aurora_behavior region_roles global_cluster_identifier global_writer_endpoint aurora_engine_version aurora_instance_class; do
  jq -e --arg name "$name" '.[$name].value != null' <<<"$outputs" >/dev/null || { echo "Falta output de infraestructura: $name" >&2; exit 65; }
done

# region_roles sólo refleja el arranque del stack. Se consulta Aurora para informar el writer
# efectivo; ambas regiones deben tener Keycloak warm (tarea corriendo y OIDC de sólo lectura).
writer_region=$(current_writer_region "$outputs")
echo "Aurora writer actual: $writer_region"

instance_class=$(jq -r '.aurora_instance_class.value' <<<"$outputs")
for region in us-east-2 us-east-1; do
  key=$(region_key "$region")
  engine_version=$(jq -r '.aurora_engine_version.value' <<<"$outputs")
  aws rds describe-db-engine-versions --region "$region" --engine aurora-postgresql --engine-version "$engine_version" --output json \
    | jq -e --arg version "$engine_version" '.DBEngineVersions | any(.EngineVersion == $version and .SupportsGlobalDatabases == true)' >/dev/null
  aws rds describe-orderable-db-instance-options --region "$region" --engine aurora-postgresql --engine-version "$engine_version" \
    --db-instance-class "$instance_class" --output json | jq -e '.OrderableDBInstanceOptions | length > 0' >/dev/null \
    || { echo "$instance_class no está disponible para aurora-postgresql $engine_version en $region" >&2; exit 70; }
  cluster=$(jq -r --arg r "$key" '.ecs_cluster_names.value[$r]' <<<"$outputs")
  service=$(jq -r --arg r "$key" '.ecs_service_names.value[$r]' <<<"$outputs")
  aws ecs describe-clusters --region "$region" --clusters "$cluster" --output json \
    | jq -e '.failures | length == 0' >/dev/null
  service_state=$(aws ecs describe-services --region "$region" --cluster "$cluster" --services "$service" --output json)
  jq -e '.failures | length == 0 and (.services | length) == 1' <<<"$service_state" >/dev/null \
    || { echo "El servicio ECS no existe o tiene fallas en $region" >&2; exit 70; }
  jq -e '.services[0].desiredCount > 0 and .services[0].runningCount >= .services[0].desiredCount' <<<"$service_state" >/dev/null \
    || { echo "ECS warm no está estable en $region" >&2; exit 70; }
  regional_url=$(jq -r --arg r "$key" '.regional_app_urls.value[$r]' <<<"$outputs")
  expected_issuer="https://$(jq -r '.app_dns_name.value' <<<"$outputs")/realms/${DEMO_REALM:-community-day}"
  curl --fail --silent --show-error "$regional_url/realms/${DEMO_REALM:-community-day}/.well-known/openid-configuration" \
    | jq -e --arg issuer "$expected_issuer" '.issuer == $issuer' >/dev/null \
    || { echo "OIDC regional no está listo en $region" >&2; exit 70; }
done
plan_arn=$(jq -r '.arc_plan_arn.value' <<<"$outputs")
aws arc-region-switch get-plan-evaluation-status --region us-east-2 --plan-arn "$plan_arn" --output json \
  | jq -e '.evaluationState | ascii_downcase == "passed"' >/dev/null || { echo "La evaluación ARC no está en passed" >&2; exit 70; }
echo "Preflight completo: writer $writer_region y ambas regiones Keycloak warm; evaluación ARC disponible."
