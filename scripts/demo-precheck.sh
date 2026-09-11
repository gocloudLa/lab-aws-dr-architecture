#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need curl; need jq; need aws
: "${KEYCLOAK_URL:?Defina KEYCLOAK_URL}"

realm=${DEMO_REALM:-community-day}
outputs=$(tf_outputs)
expected_issuer="https://$(jq -er '.app_dns_name.value' <<<"$outputs")/realms/$realm"
curl --fail --silent --show-error "$KEYCLOAK_URL/realms/$realm/.well-known/openid-configuration" \
  | jq -e --arg issuer "$expected_issuer" '.issuer == $issuer' >/dev/null

# Se consulta el writer efectivo para que el precheck siga siendo válido después de un
# switchover. La región reader sólo debe conservar su capacidad warm programada.
writer_region=$(current_writer_region "$outputs")
echo "Aurora writer actual: $writer_region"
for region in us-east-2 us-east-1; do
  key=$(region_key "$region")
  cluster=$(jq -er --arg key "$key" '.ecs_cluster_names.value[$key]' <<<"$outputs")
  service=$(jq -er --arg key "$key" '.ecs_service_names.value[$key]' <<<"$outputs")
  service_state=$(aws ecs describe-services --region "$region" --cluster "$cluster" --services "$service" --output json)
  jq -e '.failures | length == 0 and (.services | length) == 1' <<<"$service_state" >/dev/null \
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
    # Warm standby: no se exige runningCount ni OIDC mientras Aurora sea reader.
    jq -e '.services[0].desiredCount > 0' <<<"$service_state" >/dev/null \
      || { echo "ECS reader debería estar warm (desiredCount > 0) en $region" >&2; exit 70; }
  fi
done
plan_arn=$(jq -er '.arc_plan_arn.value' <<<"$outputs")
behavior=$(jq -er '.arc_aurora_behavior.value' <<<"$outputs")
aws arc-region-switch get-plan-evaluation-status --region us-east-2 --plan-arn "$plan_arn" --output json \
  | jq --arg behavior "$behavior" '{planArn,evaluationState,lastEvaluationTime,configuredAuroraBehavior:$behavior,warnings}'
