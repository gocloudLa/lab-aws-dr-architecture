#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need curl; need jq; need aws
: "${KEYCLOAK_URL:?Defina KEYCLOAK_URL}"

realm=${DEMO_REALM:-community-day}
expected_issuer="https://$(output_value app_dns_name)/realms/$realm"
curl --fail --silent --show-error "$KEYCLOAK_URL/realms/$realm/.well-known/openid-configuration" \
  | jq -e --arg issuer "$expected_issuer" '.issuer == $issuer' >/dev/null

# Pilot light: sólo la región activa (rol inicial "writer" en el stack) debe estar warm
# y servir OIDC regional. La región en espera arranca en 0 tareas a propósito; correr
# este precheck después de un switchover exige antes confirmar a mano cuál región quedó activa.
primary_region=$(output_value region_roles | jq -r '.primary.region')
for region in us-east-2 us-east-1; do
  cluster=$(map_value ecs_cluster_names "$region")
  service=$(map_value ecs_service_names "$region")
  service_state=$(aws ecs describe-services --region "$region" --cluster "$cluster" --services "$service" --output json)
  jq -e '.failures | length == 0 and (.services | length) == 1' <<<"$service_state" >/dev/null \
    || { echo "El servicio ECS no existe o tiene fallas en $region" >&2; exit 70; }
  jq '{region:"'"$region"'", desired:.services[0].desiredCount, running:.services[0].runningCount, deployments:.services[0].deployments|length}' <<<"$service_state"
  if [[ "$region" == "$primary_region" ]]; then
    jq -e '.services[0].desiredCount > 0 and .services[0].runningCount >= .services[0].desiredCount' <<<"$service_state" >/dev/null \
      || { echo "ECS primario no está warm y estable en $region" >&2; exit 70; }
    regional_url=$(map_value regional_app_urls "$region")
    curl --fail --silent --show-error "$regional_url/realms/$realm/.well-known/openid-configuration" \
      | jq -e --arg issuer "$expected_issuer" '.issuer == $issuer' >/dev/null \
      || { echo "OIDC regional no está listo en $region" >&2; exit 70; }
  else
    jq -e '.services[0].desiredCount == 0' <<<"$service_state" >/dev/null \
      || { echo "ECS secundario debería estar en pilot light (desiredCount=0) en $region" >&2; exit 70; }
  fi
done
aws arc-region-switch get-plan-evaluation-status --region us-east-2 --plan-arn "$(output_value arc_plan_arn)" --output json \
  | jq --arg behavior "$(output_value arc_aurora_behavior)" '{planArn,evaluationState,lastEvaluationTime,configuredAuroraBehavior:$behavior,warnings}'
