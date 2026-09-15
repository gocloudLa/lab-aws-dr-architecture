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
  local explicit_url=$1 region=$2 short_region
  if [[ -n "$explicit_url" ]]; then
    printf '%s' "$explicit_url"
    return
  fi
  # Lee sólo la capa project: durante tg-apply los workloads todavía no existen.
  need terragrunt
  short_region=$(region_short "$region")
  tg_layer_outputs "project/drarch-${short_region}/laboratory" \
    | jq -er '.ecr_repository_url.value'
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

existing_tag_digest() {
  local repository_url=$1 region=$2 repository_name images
  repository_name=${repository_url#*/}
  images=$(aws ecr describe-images \
    --region "$region" \
    --repository-name "$repository_name" \
    --output json)
  jq -r --arg tag "$tag" \
    '[.imageDetails[]? | select((.imageTags // []) | index($tag)) | .imageDigest][0] // empty' \
    <<< "$images"
}

primary_existing_digest=$(existing_tag_digest "$primary_repository" "$primary_region")
secondary_existing_digest=$(existing_tag_digest "$secondary_repository" "$secondary_region")

if [[ -n "$primary_existing_digest" || -n "$secondary_existing_digest" ]]; then
  if [[ -n "$primary_existing_digest" && "$primary_existing_digest" == "$secondary_existing_digest" ]]; then
    if [[ "${ALLOW_EXISTING_TAG:-no}" == "yes" ]]; then
      echo "La imagen $tag ya existe con digest $primary_existing_digest en ambos ECR; se reutiliza."
      exit 0
    fi
    echo "El tag $tag ya existe en ambos ECR; los repositorios son inmutables" >&2
    exit 65
  fi
  echo "El tag $tag existe sólo en una región o sus digests no coinciden; no se modificará" >&2
  exit 65
fi

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
