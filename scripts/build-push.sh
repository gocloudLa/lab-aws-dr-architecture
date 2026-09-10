#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need aws; need docker; need jq
tag=${1:?Uso: scripts/build-push.sh TAG}
[[ "$tag" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || { echo "TAG inválido" >&2; exit 64; }

primary_region=${AWS_PRIMARY_REGION:-us-east-2}
secondary_region=${AWS_SECONDARY_REGION:-us-east-1}
require_region "$primary_region"
require_region "$secondary_region"
[[ "$primary_region" != "$secondary_region" ]] || { echo "Las regiones primaria y secundaria deben ser distintas" >&2; exit 64; }

resolve_repository() {
  local explicit_url=$1 region=$2
  if [[ -n "$explicit_url" ]]; then
    printf '%s' "$explicit_url"
    return
  fi
  need terraform
  map_value ecr_repository_urls "$region"
}

primary_repository=$(resolve_repository "${ECR_REPOSITORY_URL_PRIMARY:-}" "$primary_region")
secondary_repository=$(resolve_repository "${ECR_REPOSITORY_URL_SECONDARY:-}" "$secondary_region")

validate_repository() {
  local repository=$1 region=$2 label=$3
  [[ "$repository" == *.dkr.ecr."$region".amazonaws.com/* ]] || {
    echo "$label no pertenece a $region" >&2
    exit 65
  }
}

validate_repository "$primary_repository" "$primary_region" "ECR primario"
validate_repository "$secondary_repository" "$secondary_region" "ECR secundario"

primary_account=${primary_repository%%.*}
secondary_account=${secondary_repository%%.*}
caller_account=$(aws sts get-caller-identity --query Account --output text)
[[ "$primary_account" == "$secondary_account" ]] || { echo "Los ECR pertenecen a cuentas AWS distintas" >&2; exit 65; }
[[ "$caller_account" == "$primary_account" ]] || { echo "La identidad AWS activa no pertenece a la cuenta de los ECR" >&2; exit 65; }

assert_tag_is_new() {
  local repository_url=$1 region=$2 label=$3 repository_name images
  repository_name=${repository_url#*/}
  images=$(aws ecr list-images \
    --region "$region" \
    --repository-name "$repository_name" \
    --filter tagStatus=TAGGED \
    --output json)
  if jq -e --arg tag "$tag" 'any(.imageIds[]?; .imageTag == $tag)' <<< "$images" >/dev/null; then
    echo "El tag $tag ya existe en el ECR $label; los repositorios son inmutables" >&2
    exit 65
  fi
}

assert_tag_is_new "$primary_repository" "$primary_region" "primario"
assert_tag_is_new "$secondary_repository" "$secondary_region" "secundario"

for entry in "$primary_region|$primary_repository" "$secondary_region|$secondary_repository"; do
  region=${entry%%|*}
  repository=${entry#*|}
  registry=${repository%%/*}
  aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"
done

local_image="aurora-dr-keycloak:$tag"
docker build --pull -t "$local_image" "$REPO_ROOT/app"
for repository in "$primary_repository" "$secondary_repository"; do
  docker tag "$local_image" "$repository:$tag"
  docker push "$repository:$tag"
done

image_digest() {
  local repository_url=$1 region=$2 repository_name
  repository_name=${repository_url#*/}
  aws ecr describe-images \
    --region "$region" \
    --repository-name "$repository_name" \
    --image-ids imageTag="$tag" \
    --query 'imageDetails[0].imageDigest' \
    --output text
}

primary_digest=$(image_digest "$primary_repository" "$primary_region")
secondary_digest=$(image_digest "$secondary_repository" "$secondary_region")
[[ "$primary_digest" == sha256:* ]] || { echo "ECR primario no devolvió un digest válido" >&2; exit 1; }
[[ "$secondary_digest" == "$primary_digest" ]] || { echo "Los digests regionales no coinciden" >&2; exit 1; }

echo "Imagen idéntica publicada con tag $tag y digest $primary_digest en ambas regiones."
