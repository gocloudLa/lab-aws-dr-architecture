#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need curl; need jq; need aws
: "${KEYCLOAK_URL:?Defina KEYCLOAK_URL}"

realm=${DEMO_REALM:-community-day}
expected_issuer="https://$(output_value app_dns_name)/realms/$realm"
curl --fail --silent --show-error "$KEYCLOAK_URL/realms/$realm/.well-known/openid-configuration" \
  | jq -e --arg issuer "$expected_issuer" '.issuer == $issuer' >/dev/null
for region in us-east-2 us-east-1; do
  cluster=$(map_value ecs_cluster_names "$region")
  service=$(map_value ecs_service_names "$region")
  service_state=$(aws ecs describe-services --region "$region" --cluster "$cluster" --services "$service" --output json)
  jq -e '.failures | length == 0 and (.services | length) == 1 and .services[0].desiredCount > 0 and .services[0].runningCount >= .services[0].desiredCount' <<<"$service_state" >/dev/null \
    || { echo "ECS no está warm y estable en $region" >&2; exit 70; }
  jq '{region:"'"$region"'", desired:.services[0].desiredCount, running:.services[0].runningCount, deployments:.services[0].deployments|length}' <<<"$service_state"
  regional_url=$(map_value regional_app_urls "$region")
  curl --fail --silent --show-error "$regional_url/realms/$realm/.well-known/openid-configuration" \
    | jq -e --arg issuer "$expected_issuer" '.issuer == $issuer' >/dev/null \
    || { echo "OIDC regional no está listo en $region" >&2; exit 70; }
done
aws arc-region-switch get-plan-evaluation-status --region us-east-2 --plan-arn "$(output_value arc_plan_arn)" --output json \
  | jq --arg behavior "$(output_value arc_aurora_behavior)" '{planArn,evaluationState,lastEvaluationTime,configuredAuroraBehavior:$behavior,warnings}'
