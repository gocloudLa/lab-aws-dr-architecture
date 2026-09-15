#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need curl; need jq
: "${KEYCLOAK_URL:?Defina KEYCLOAK_URL, por ejemplo https://app.example.com}"
: "${KC_BOOTSTRAP_ADMIN_USERNAME:?Defina KC_BOOTSTRAP_ADMIN_USERNAME}"
: "${KC_BOOTSTRAP_ADMIN_PASSWORD:?Defina KC_BOOTSTRAP_ADMIN_PASSWORD}"
realm=${DEMO_REALM:-community-day}
demo_user=${DEMO_USERNAME:-operador}
demo_email=${DEMO_EMAIL:-"${demo_user}@example.invalid"}
demo_password=${DEMO_PASSWORD:?Defina DEMO_PASSWORD}

token=$(curl --fail --silent --show-error \
  --data-urlencode client_id=admin-cli --data-urlencode grant_type=password \
  --data-urlencode "username=$KC_BOOTSTRAP_ADMIN_USERNAME" --data-urlencode "password=$KC_BOOTSTRAP_ADMIN_PASSWORD" \
  "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" | jq -er .access_token)
auth=(-H "Authorization: Bearer $token" -H 'Content-Type: application/json')

if ! curl --fail --silent "${auth[@]}" "$KEYCLOAK_URL/admin/realms/$realm" >/dev/null 2>&1; then
  payload=$(jq -nc --arg realm "$realm" '{realm:$realm,enabled:true,displayName:"AWS Community Day · Aurora DR",registrationAllowed:false,resetPasswordAllowed:true}')
  curl --fail --silent --show-error "${auth[@]}" -d "$payload" "$KEYCLOAK_URL/admin/realms" >/dev/null
fi

user_id=$(curl --fail --silent --show-error "${auth[@]}" --get --data-urlencode "username=$demo_user" --data-urlencode exact=true \
  "$KEYCLOAK_URL/admin/realms/$realm/users" | jq -r '.[0].id // empty')
if [[ -z "$user_id" ]]; then
  payload=$(jq -nc --arg username "$demo_user" --arg email "$demo_email" '{username:$username,email:$email,enabled:true,emailVerified:true,firstName:"Operador",lastName:"Demo"}')
  location=$(curl --fail --silent --show-error -D - -o /dev/null "${auth[@]}" -d "$payload" "$KEYCLOAK_URL/admin/realms/$realm/users" | awk 'tolower($1)=="location:" {gsub("\r", "", $2); print $2}')
  user_id=${location##*/}
fi
current=$(curl --fail --silent --show-error "${auth[@]}" "$KEYCLOAK_URL/admin/realms/$realm/users/$user_id")
profile=$(jq --arg email "$demo_email" '.email=$email | .emailVerified=true | .firstName=(.firstName // "Operador") | .lastName=(.lastName // "Demo") | del(.access)' <<<"$current")
curl --fail --silent --show-error "${auth[@]}" -X PUT -d "$profile" "$KEYCLOAK_URL/admin/realms/$realm/users/$user_id" >/dev/null
credential=$(jq -nc --arg value "$demo_password" '{type:"password",value:$value,temporary:false}')
curl --fail --silent --show-error "${auth[@]}" -X PUT -d "$credential" "$KEYCLOAK_URL/admin/realms/$realm/users/$user_id/reset-password" >/dev/null
echo "Realm $realm y usuario $demo_user inicializados de forma idempotente."
