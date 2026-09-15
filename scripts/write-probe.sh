#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need curl; need jq
: "${KEYCLOAK_URL:?Defina KEYCLOAK_URL}"
: "${KC_BOOTSTRAP_ADMIN_USERNAME:?Defina KC_BOOTSTRAP_ADMIN_USERNAME}"
: "${KC_BOOTSTRAP_ADMIN_PASSWORD:?Defina KC_BOOTSTRAP_ADMIN_PASSWORD}"
realm=${DEMO_REALM:-community-day}; username=${DEMO_USERNAME:-operador}
probe_id=${PROBE_ID:-"probe-$(date -u +%Y%m%dT%H%M%S)-$$"}
connect_timeout=${CURL_CONNECT_TIMEOUT_SECONDS:-3}
max_time=${CURL_MAX_TIME_SECONDS:-10}
[[ "$connect_timeout" =~ ^[1-9][0-9]*$ ]] || { echo "CURL_CONNECT_TIMEOUT_SECONDS debe ser un entero positivo" >&2; exit 64; }
[[ "$max_time" =~ ^[1-9][0-9]*$ ]] || { echo "CURL_MAX_TIME_SECONDS debe ser un entero positivo" >&2; exit 64; }
curl_options=(--connect-timeout "$connect_timeout" --max-time "$max_time" --fail --silent --show-error)
start_epoch=$(date +%s)

token=$(curl "${curl_options[@]}" --data-urlencode client_id=admin-cli --data-urlencode grant_type=password \
  --data-urlencode "username=$KC_BOOTSTRAP_ADMIN_USERNAME" --data-urlencode "password=$KC_BOOTSTRAP_ADMIN_PASSWORD" \
  "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" | jq -er .access_token)
auth=(-H "Authorization: Bearer $token" -H 'Content-Type: application/json')
user=$(curl "${curl_options[@]}" "${auth[@]}" --get --data-urlencode "username=$username" --data-urlencode exact=true "$KEYCLOAK_URL/admin/realms/$realm/users" | jq -e '.[0]')
user_id=$(jq -r .id <<<"$user")
payload=$(jq --arg probe "$probe_id" '.lastName = $probe | del(.access)' <<<"$user")

# Un PUT repetido lleva el mismo valor: cada intento explícito de sonda es idempotente.
curl "${curl_options[@]}" "${auth[@]}" -X PUT -d "$payload" "$KEYCLOAK_URL/admin/realms/$realm/users/$user_id" >/dev/null
observed=$(curl "${curl_options[@]}" "${auth[@]}" "$KEYCLOAK_URL/admin/realms/$realm/users/$user_id" | jq -er '.lastName')
[[ "$observed" == "$probe_id" ]] || { echo "La lectura no confirmó la escritura" >&2; exit 1; }
end_epoch=$(date +%s)
jq -n --arg probeId "$probe_id" --arg observedAt "$(date -u +%FT%TZ)" --argjson elapsedSeconds "$((end_epoch-start_epoch))" \
  '{probeId:$probeId,confirmed:true,observedAt:$observedAt,elapsedSeconds:$elapsedSeconds}'
