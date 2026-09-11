# Guía de la demo, punta a punta

Reproducible en cualquier cuenta AWS. Los pasos con AWS **no fueron ejecutados** en este repo: la validación disponible es local. Ver [Validación local](#validación-local).

## Prerrequisitos

- Terraform ≥ 1.10, AWS CLI v2, Docker y `jq`.
- Una cuenta AWS con permisos sobre RDS, ECS, ECR, ELB, VPC, Route 53, IAM, SSM y ARC Region switch.
- Una zona pública Route 53 con un dominio propio.
- Dos certificados ACM, uno por región (`us-east-2` y `us-east-1`), que cubran `app.<dominio>` y `<key>.app.<dominio>`.

## Elegir orquestación

Durante la migración conviven dos:

| Orquestación | Cuándo | Cómo |
|---|---|---|
| **`terragrunt/`** (recomendada) | Red existente. Un comando, sin condiciones de carrera | `make tg-apply` |
| `terraform/examples/lab` | Stack anterior, se conserva hasta validar la migración | `IAC_MODE=terraform` + `terraform apply` por etapas |
| `terraform/examples/complete` | Cuenta vacía, crea también VPC/NAT/peering | ídem |

El stack Terragrunt separa el despliegue en seis capas porque los wrappers resuelven ALB,
target groups y clúster ECS con data sources internos que no se pueden expandir en un único
state. Ver [terragrunt/README.md](../terragrunt/README.md) para el detalle y el DAG.

Los scripts de `scripts/` leen los outputs de las capas de Terragrunt por defecto; exportar
`IAC_MODE=terraform` para operar la demo contra el stack anterior.

### Variantes del stack Terraform

| Variante | Cuándo | Qué crea |
|---|---|---|
| `terraform/examples/complete` | Cuenta vacía, demo desde cero | VPC, NAT, subredes y peering, más todo el stack |
| `terraform/examples/lab` | Ya tenés red | Sólo el stack, sobre tu VPC/NAT/subredes |

`lab` resuelve la red por tag `Name`, no por ID. Tu VPC debe tener subredes públicas (ALB), privadas con salida por NAT (ECS) y de base de datos, y un security group por defecto etiquetado. **No hace falta peering ni conectividad interregional**: cada Keycloak conecta siempre al clúster Aurora de su propia región (patrón pilot light, ver [architecture.md](architecture.md)). Los nombres se declaran en `primary_network` / `secondary_network`.

Los comandos siguientes usan `complete`; para `lab`, cambiar el directorio y exportar `TF_DIR=terraform/examples/lab` antes de correr los scripts.

## 1. Configurar

```bash
cd terraform/examples/complete
cp terraform.tfvars.example terraform.tfvars   # completar zona, dominio y certificados
terraform init
```

## 2. Bootstrap: infraestructura sin imagen

`ecs_desired_count = 0` crea los ECR y el resto de la infraestructura sin intentar arrancar una imagen que todavía no existe.

```bash
terraform plan -out=infra.tfplan
terraform show infra.tfplan
terraform apply infra.tfplan
terraform output
```

Guardá los outputs no sensibles: `ecr_repository_urls`, `global_writer_endpoint`, `regional_app_urls`, `arc_plan_arn`.

## 3. Publicar la imagen en ambas regiones

Una sola imagen, el mismo tag en los dos ECR. Los repositorios son inmutables: un tag no se repisa.

```bash
cd ../../..
make build-push TAG=demo-v1 TF_DIR=terraform/examples/complete
```

## 4. Habilitar el servicio en la región primaria

En `terraform.tfvars`: `container_image_tag = "demo-v1"` y `ecs_desired_count = 1`.

```bash
cd terraform/examples/complete
terraform plan -out=services.tfplan
terraform show services.tfplan
terraform apply services.tfplan
```

`ecs_desired_count` sólo controla la región primaria. La secundaria es **pilot light**: su Terraform la fija en 0 tareas sin importar este valor, porque su clúster Aurora es réplica de sólo lectura y Keycloak no podría completar su migración de escritura contra él. El plan de ARC la escala durante la conmutación, después de promover Aurora (ver paso 7).

## 5. Cargar el realm de demo

Las credenciales las genera Terraform y quedan en parámetros SSM cifrados, creados por el wrapper de ECS Service:

```bash
region=us-east-2
prefix=gcl-lab-drarch-keycloak-app
get() { aws ssm get-parameter --with-decryption --region "$region" \
  --name "$prefix-$1" --query Parameter.Value --output text; }

export KEYCLOAK_URL="https://app.<dominio>"
export KC_BOOTSTRAP_ADMIN_USERNAME=$(get KC_BOOTSTRAP_ADMIN_USERNAME)
export KC_BOOTSTRAP_ADMIN_PASSWORD=$(get KC_BOOTSTRAP_ADMIN_PASSWORD)
export DEMO_PASSWORD="<una contraseña para el usuario de demo>"

cd ../../.. && make bootstrap
```

## 6. Preflight

```bash
make preflight TF_DIR=terraform/examples/complete
make demo-precheck TF_DIR=terraform/examples/complete
```

Exigen la tarea ECS primaria en ejecución y su endpoint regional saludable. La región secundaria está en pilot light (0 tareas) hasta la conmutación, así que su ECS no se valida acá. Consultan AWS; no prueban por sí solos writer, DNS, TLS ni RTO/RPO.

## 7. Ensayo de conmutación

Antes de arrancar: registrar commit, tag, hora UTC, writer actual y los dos hostnames regionales. Crear un usuario en Admin Console y actualizar un perfil en Account Console, o usar `make write-probe`, para tener un dato de control.

```bash
# 1. Simular la caída de la aplicación en la región activa
make fault-stop REGION=us-east-2 TF_DIR=terraform/examples/complete

# 2. Conmutar. switchover no espera pérdida; failover la acepta explícitamente.
make arc-start OPERATION=switchover TARGET_REGION=us-east-1 TF_DIR=terraform/examples/complete
# ACCEPT_DATA_LOSS=yes make arc-start OPERATION=failover TARGET_REGION=us-east-1 TF_DIR=terraform/examples/complete

# 3. Seguir la ejecución
make arc-poll OPERATION=switchover EXECUTION_ID=EXECUTION_ID TF_DIR=terraform/examples/complete
```

El plan hace exactamente tres cosas, en orden estricto: promueve Aurora en la región destino, escala el ECS de esa región de 0 a N tareas (pilot light: recién ahí arranca Keycloak, con su clúster local ya promovido y escribible), y por último mueve el health check de Route 53. El paso de ECS sí es un gate: ARC espera a que la capacidad pedida esté corriendo (o el timeout) antes de tocar el DNS, así que Route 53 no publica un ALB sin backend. No hay, en cambio, comprobación de que Keycloak ya pasó su propio health check de aplicación más allá de lo que reporta el ECS. Registrá cualquier `5xx`, fallo de login o intervalo de indisponibilidad, incluido el tiempo de arranque de Keycloak en la región destino.

Desde un cliente limpio: resolver `app.<dominio>`, entrar, y verificar que el usuario y el perfil de control siguen ahí. La primera operación confirmada cierra el cronómetro. Comparar timestamps antes y después para el RPO; si no se puede medir, declararlo **no medido**.

## 8. Failback

Recuperar la región original, confirmar writer y reader reales y la salud de ambos Keycloak, y ejecutar un switchover planificado inverso. La región que vuelve a quedar en espera queda en pilot light (el propio plan de ARC no la vuelve a bajar a 0 automáticamente en el sentido inverso más que escalando el destino del nuevo switchover); si hace falta bajarla a 0 de forma explícita, usar `aws ecs update-service --desired-count 0` sobre esa región. Correr `terraform plan` después de cada promoción: el writer cambia fuera de Terraform, aunque `desired_count` del ECS está en `ignore_changes` y no genera drift.

## 9. Desmontar

Detener ambos servicios ECS (`aws ecs update-service --desired-count 0` en la región que haya quedado activa; la otra ya puede seguir en pilot light) y confirmar que no haya ejecuciones ARC activas. Conservar un snapshot manual si hay datos a retener. `deletion_protection` está en `true` por defecto: bajarlo a `false` en `terraform.tfvars` sólo cuando el borrado esté autorizado.

```bash
terraform plan -destroy -out=destroy.tfplan
terraform show destroy.tfplan
terraform apply destroy.tfplan
```

Si AWS rechaza el orden de borrado, parar y revisar el estado real; no forzar sobre una topología sin revisar.

## Validación local

Sin credenciales AWS y sin crear nada:

```bash
make init       # baja wrappers y providers de ambos examples
make validate   # fmt, validate y contratos estáticos
docker compose -f .docker/docker-compose.yml up --build   # Keycloak contra un PostgreSQL local
```

`make validate` no prueba Aurora, ARC, Route 53, TLS contra RDS, cuotas, permisos ni RTO/RPO. Los parámetros de los wrappers son mapas de tipo `any`: `terraform validate` no verifica sus claves. La única prueba real es el ensayo en AWS.
