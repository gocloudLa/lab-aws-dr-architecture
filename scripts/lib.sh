#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Por defecto apunta al example de laboratorio. Exportar TF_DIR para usar otro root,
# por ejemplo terraform/examples/complete.
TF_DIR=${TF_DIR:-"$REPO_ROOT/terraform/examples/lab"}
AWS_PAGER=""
export AWS_PAGER

need() { command -v "$1" >/dev/null || { echo "Falta la herramienta requerida: $1" >&2; exit 69; }; }
tf_outputs() { terraform -chdir="$TF_DIR" output -json; }
output_value() {
  local name=$1
  tf_outputs | jq -er --arg name "$name" '.[$name].value'
}
map_value() {
  local output=$1 key=$2
  key=$(region_key "$key")
  output_value "$output" | jq -er --arg key "$key" '.[$key]'
}
region_key() { printf '%s' "$1" | tr '-' '_'; }
require_region() { case "$1" in us-east-2|us-east-1) ;; *) echo "Región fuera de la demo: $1" >&2; exit 64;; esac; }
temp_json() { mktemp "${TMPDIR:-/tmp}/aurora-dr.XXXXXX.json"; }
