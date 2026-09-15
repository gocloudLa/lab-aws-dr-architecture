#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
for tool in aws jq curl; do need "$tool"; done
: "${KEYCLOAK_URL:?Defina KEYCLOAK_URL}"

aws sts get-caller-identity --output json | jq '{Account,Arn}'
realm=${DEMO_REALM:-community-day}
outputs=$(tf_outputs)
for name in ecr_repository_urls ecs_cluster_names ecs_service_names regional_app_urls app_dns_name arc_plan_arn arc_aurora_behavior region_roles global_cluster_identifier global_writer_endpoint aurora_engine_version aurora_instance_class; do
  jq -e --arg name "$name" '.[$name].value != null' <<<"$outputs" >/dev/null \
    || { echo "Falta output de infraestructura: $name" >&2; exit 65; }
done
expected_issuer="https://$(jq -er '.app_dns_name.value' <<<"$outputs")/realms/$realm"
curl --fail --silent --show-error "$KEYCLOAK_URL/realms/$realm/.well-known/openid-configuration" \
  | jq -e --arg issuer "$expected_issuer" '.issuer == $issuer' >/dev/null

# Se consulta el writer efectivo para que el precheck siga siendo válido después de un
# switchover. El writer debe estar saludable; la reader sólo conserva capacidad deseada.
writer_region=$(current_writer_region "$outputs")
echo "Aurora writer actual: $writer_region"
instance_class=$(jq -er '.aurora_instance_class.value' <<<"$outputs")
engine_version=$(jq -er '.aurora_engine_version.value' <<<"$outputs")
for region in us-east-2 us-east-1; do
  key=$(region_key "$region")
  aws rds describe-db-engine-versions --region "$region" --engine aurora-postgresql \
    --engine-version "$engine_version" --output json \
    | jq -e --arg version "$engine_version" \
      '.DBEngineVersions | any(.EngineVersion == $version and .SupportsGlobalDatabases == true)' >/dev/null
  aws rds describe-orderable-db-instance-options --region "$region" --engine aurora-postgresql \
    --engine-version "$engine_version" --db-instance-class "$instance_class" --output json \
    | jq -e '.OrderableDBInstanceOptions | length > 0' >/dev/null \
    || { echo "$instance_class no está disponible para aurora-postgresql $engine_version en $region" >&2; exit 70; }
  cluster=$(jq -er --arg key "$key" '.ecs_cluster_names.value[$key]' <<<"$outputs")
  service=$(jq -er --arg key "$key" '.ecs_service_names.value[$key]' <<<"$outputs")
  aws ecs describe-clusters --region "$region" --clusters "$cluster" --output json \
    | jq -e '.failures | length == 0' >/dev/null
  service_state=$(aws ecs describe-services --region "$region" --cluster "$cluster" --services "$service" --output json)
  jq -e '(.failures | length) == 0 and (.services | length) == 1' <<<"$service_state" >/dev/null \
    || { echo "El servicio ECS no existe o tiene fallas en $region" >&2; exit 70; }
  jq '{region:"'"$region"'", desired:.services[0].desiredCount, running:.services[0].runningCount, deployments:.services[0].deployments|length}' <<<"$service_state"
  if [[ "$region" == "$writer_region" ]]; then
    jq -e '.services[0].desiredCount > 0 and .services[0].runningCount >= .services[0].desiredCount' <<<"$service_state" >/dev/null \
      || { echo "ECS de la región writer no está estable en $region" >&2; exit 70; }
    regional_url=$(jq -er --arg key "$key" '.regional_app_urls.value[$key]' <<<"$outputs")
    curl --fail --silent --show-error "$regional_url/realms/$realm/.well-known/openid-configuration" \
      | jq -e --arg issuer "$expected_issuer" '.issuer == $issuer' >/dev/null \
      || { echo "OIDC regional no está listo en $region" >&2; exit 70; }
  else
    # Reader warm: sólo se exige desiredCount > 0, no ejecución ni salud antes de la promoción.
    jq -e '.services[0].desiredCount > 0' <<<"$service_state" >/dev/null \
      || { echo "ECS reader no tiene capacidad deseada en $region" >&2; exit 70; }
    echo "ECS reader warm en $region: desiredCount > 0; ejecución y salud no requeridas hasta la promoción."
  fi
done
plan_arn=$(jq -er '.arc_plan_arn.value' <<<"$outputs")
behavior=$(jq -er '.arc_aurora_behavior.value' <<<"$outputs")
evaluation=$(aws arc-region-switch get-plan-evaluation-status --region us-east-2 --plan-arn "$plan_arn" --output json)
jq -e '.evaluationState | ascii_downcase == "passed"' <<<"$evaluation" >/dev/null \
  || { echo "La evaluación ARC no está en passed" >&2; exit 70; }
jq --arg behavior "$behavior" \
  '{planArn,evaluationState,lastEvaluationTime,configuredAuroraBehavior:$behavior,warnings}' \
  <<<"$evaluation"
echo "Demo precheck completo: writer $writer_region saludable, reader con capacidad deseada y evaluación ARC passed."
