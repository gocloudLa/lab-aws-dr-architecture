#!/usr/bin/env bash
# Contratos estáticos sobre el código. No consulta AWS ni ejecuta Terraform.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
stack="$repo_root/terraform/modules/dr-architecture"
region_module="$repo_root/terraform/modules/keycloak-region"

# El plan de ARC tiene exactamente dos pasos: primero Aurora, después DNS.
step_count=$(grep -Ec 'execution_block_type[[:space:]]*=' "$stack/arc.tf" || true)
[[ "$step_count" -eq 2 ]] || { echo "ARC debe contener exactamente dos execution blocks; contiene $step_count" >&2; exit 1; }

# No deben reaparecer piezas del diseño retirado.
if grep -RInE --exclude-dir=.terraform 'aws_db_proxy|DB_PROXY_ENDPOINTS|CustomActionLambda|aws_route53_zone|proxy_writer_gate' \
  "$repo_root/terraform" "$repo_root/app"; then
  echo "Quedaron referencias activas al diseño retirado" >&2
  exit 1
fi

# Keycloak se conecta siempre al Global Writer Endpoint, en las dos regiones.
grep -Eq 'global_writer_endpoint[[:space:]]*=[[:space:]]*aws_rds_global_cluster\.this\.endpoint' "$stack/main.tf"
grep -Eq 'DB_HOST[[:space:]]*=[[:space:]]*var\.global_writer_endpoint' "$region_module/main.tf"

# Contrato TLS de la imagen.
grep -Eq 'sslmode=verify-full&sslrootcert=' "$repo_root/app/entrypoint.sh"
grep -Eq 'global-bundle\.pem' "$repo_root/app/Dockerfile"

# No mezclar orígenes de módulos: sólo wrappers de gocloudLa o rutas relativas locales.
# hashicorp/* queda permitido porque es el origen de los providers, no de los módulos.
foreign=$(grep -RhoE --exclude-dir=.terraform '^[[:space:]]*source[[:space:]]*=[[:space:]]*"[^"]+"' "$repo_root/terraform" \
  | sed 's/.*"\(.*\)"/\1/' \
  | grep -Ev '^(\.|gocloudLa/|hashicorp/)' || true)
if [[ -n "$foreign" ]]; then
  echo "Hay módulos de un origen distinto a gocloudLa:" >&2
  echo "$foreign" >&2
  exit 1
fi

# El wrapper del servicio aún resuelve el clúster por data source. Red, subredes y ALB
# llegan como valores explícitos, por lo que sólo el clúster conserva depends_on.
grep -Eq 'depends_on[[:space:]]*=[[:space:]]*\[module\.ecs\]' "$region_module/main.tf"

echo "Contratos Global Writer Endpoint/ARC/naming: OK"
