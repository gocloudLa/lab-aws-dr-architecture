#!/usr/bin/env bash
# Muestra el contrato de outputs que consumen el resto de los scripts, ya agregado desde
# las capas de Terragrunt (o desde el root module único si IAC_MODE=terraform).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need jq

tf_outputs | jq 'with_entries(.value |= .value)'
