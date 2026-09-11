#!/usr/bin/env bash
# Contratos estáticos sobre el código. No consulta AWS ni ejecuta Terragrunt.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)

# Stack Terragrunt: única fuente de la orquestación por capas.
tg="$repo_root/terragrunt"
tg_arc="$tg/workload/drarch-arc/laboratory"
tg_wl_use2="$tg/workload/drarch-use2/laboratory"
tg_wl_use1="$tg/workload/drarch-use1/laboratory"
tg_proj_use2="$tg/project/drarch-use2/laboratory"

fail() { echo "$1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Contratos del stack Terragrunt
# ---------------------------------------------------------------------------

# Seis capas, ni más ni menos: cada una existe para romper una dependencia que un único
# state no puede resolver.
for layer in \
  project/drarch-global/laboratory \
  project/drarch-use2/laboratory \
  project/drarch-use1/laboratory \
  workload/drarch-use2/laboratory \
  workload/drarch-use1/laboratory \
  workload/drarch-arc/laboratory; do
  [[ -f "$tg/$layer/terragrunt.hcl" ]] || fail "Falta la capa Terragrunt: $layer"
done

# El plan de ARC tiene exactamente tres pasos: Aurora, escalado de ECS y por último DNS.
step_count=$(grep -Ec 'execution_block_type[[:space:]]*=' "$tg_arc/main.tf" || true)
[[ "$step_count" -eq 3 ]] || fail "ARC debe contener exactamente tres execution blocks; contiene $step_count"

# El orden importa: si DNS conmutara antes de escalar, Route 53 publicaría un ALB sin backend.
aurora_line=$(grep -n 'execution_block_type = "AuroraGlobalDatabase"' "$tg_arc/main.tf" | cut -d: -f1)
ecs_line=$(grep -n 'execution_block_type = "ECSServiceScaling"' "$tg_arc/main.tf" | cut -d: -f1)
dns_line=$(grep -n 'execution_block_type = "Route53HealthCheck"' "$tg_arc/main.tf" | cut -d: -f1)
[[ -n "$aurora_line" && -n "$ecs_line" && -n "$dns_line" ]] || fail "Faltan pasos en el plan de ARC"
(( aurora_line < ecs_line && ecs_line < dns_line )) || fail "El plan de ARC debe ordenar Aurora, luego ECS y por último DNS"

# Cada Keycloak conecta al clúster Aurora de su propia región, nunca al Global Writer Endpoint
# compartido, así que no hace falta peering entre VPC.
grep -Eq 'DB_HOST = var\.db_host' "$tg_wl_use2/main.tf" || fail "El workload use2 debe usar var.db_host como DB_HOST"
grep -Eq 'aurora_cluster_endpoint' "$tg_wl_use2/terragrunt.hcl" || fail "db_host debe venir del endpoint del clúster regional"

# Warm standby: ambas regiones corren 1 tarea y aceptan el endpoint local aunque sea reader.
grep -Eq 'ecs_desired_count = 1' "$tg_wl_use1/terragrunt.hcl" || fail "El workload use1 debe correr warm (1 tarea)"
for workload_main in "$tg_wl_use2/main.tf" "$tg_wl_use1/main.tf"; do
  grep -Fq 'KC_DB_URL_PROPERTIES = "?targetServerType=any"' "$workload_main" \
    || fail "Cada workload regional debe configurar KC_DB_URL_PROPERTIES con targetServerType=any"
done

# Los chequeos operativos deben consultar el writer efectivo; region_roles sólo refleja el
# estado inicial y no cambia después de una conmutación.
grep -Fq 'writer_region=$(current_writer_region "$outputs")' "$repo_root/scripts/preflight.sh" \
  || fail "preflight debe validar la región writer efectiva"
grep -Fq 'writer_region=$(current_writer_region "$outputs")' "$repo_root/scripts/demo-precheck.sh" \
  || fail "demo-precheck debe validar la región writer efectiva"

# El ingress de Aurora sólo abre el CIDR local: si reapareciera el CIDR remoto, volvería la
# dependencia de peering que este diseño elimina.
grep -Eq 'cidr_blocks = join\(",", local\.app_cidr_blocks\)' "$tg_proj_use2/main.tf" \
  || fail "El ingress de Aurora debe usar sólo los CIDR de su propia región"
grep -q 'peer_app_cidr_blocks' "$tg_proj_use2/main.tf" && fail "Reapareció peer_app_cidr_blocks: eso reintroduce la dependencia de peering"

# Aurora Global Database no admite clases burstable.
grep -Eq 'contains\(\["t3", "t4g"\]' "$tg_proj_use2/variables.tf" \
  || fail "Falta la validación que rechaza clases burstable en aurora_instance_class"

# ---------------------------------------------------------------------------
# Contratos comunes
# ---------------------------------------------------------------------------

# No deben reaparecer piezas del diseño retirado. Se excluyen .terraform/.terragrunt-cache
# (módulos de terceros cacheados, que sí usan aws_route53_zone como data source legítimo)
# y los archivos de estado.
if grep -RInE --exclude-dir=.terraform --exclude-dir=.terragrunt-cache --exclude-dir=.tfstate \
  --exclude='terraform.tfstate*' \
  'aws_db_proxy|DB_PROXY_ENDPOINTS|CustomActionLambda|proxy_writer_gate' \
  "$repo_root/terragrunt" "$repo_root/app"; then
  fail "Quedaron referencias activas al diseño retirado"
fi

# Contrato TLS de la imagen.
grep -Eq 'sslmode=verify-full&sslrootcert=' "$repo_root/app/entrypoint.sh" || fail "Falta el contrato sslmode=verify-full"
grep -Fq 'additional_db_url_properties=${KC_DB_URL_PROPERTIES:-}' "$repo_root/app/entrypoint.sh" \
  || fail "El entrypoint debe incorporar KC_DB_URL_PROPERTIES a la URL JDBC efectiva"
grep -Eq 'global-bundle\.pem' "$repo_root/app/Dockerfile" || fail "Falta el bundle de CA de RDS"

# No mezclar orígenes de módulos: sólo wrappers de gocloudLa o rutas relativas locales.
# hashicorp/* queda permitido porque es el origen de los providers, no de los módulos.
foreign=$(grep -RhoE --exclude-dir=.terraform --exclude-dir=.terragrunt-cache \
  '^[[:space:]]*source[[:space:]]*=[[:space:]]*"[^"]+"' "$repo_root/terragrunt" \
  | sed 's/.*"\(.*\)"/\1/' \
  | grep -Ev '^(\.|gocloudLa/|hashicorp/)' || true)
if [[ -n "$foreign" ]]; then
  echo "Hay módulos de un origen distinto a gocloudLa:" >&2
  echo "$foreign" >&2
  exit 1
fi

echo "Contratos de capas/ARC/naming: OK"
