# Guía de la demo, punta a punta

Reproducible en cualquier cuenta AWS. Los pasos con AWS **no fueron ejecutados** en este repo: la validación disponible es local. Ver [Validación local](#validación-local).

## Prerrequisitos

- Terraform ≥ 1.10, AWS CLI v2, Docker y `jq`.
- Una cuenta AWS con permisos sobre RDS, ECS, ECR, ELB, VPC, Route 53, IAM, SSM y ARC Region switch.
- Una zona pública Route 53 con un dominio propio.
- Dos certificados ACM, uno por región (`us-east-2` y `us-east-1`), que cubran `app.<dominio>` y `<key>.app.<dominio>`.

## Elegir variante

| Variante | Cuándo | Qué crea |
|---|---|---|
| `terraform/examples/complete` | Cuenta vacía, demo desde cero | VPC, NAT, subredes y peering, más todo el stack |
| `terraform/examples/lab` | Ya tenés red | Sólo el stack, sobre tu VPC/NAT/subredes |

`lab` resuelve la red por tag `Name`, no por ID. Tu VPC debe tener subredes públicas (ALB), privadas con salida por NAT (ECS) y de base de datos, un security group por defecto etiquetado, y conectividad PostgreSQL con la otra región. Los nombres se declaran en `primary_network` / `secondary_network`.

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

## 4. Habilitar los servicios

En `terraform.tfvars`: `container_image_tag = "demo-v1"` y `ecs_desired_count = 1`.

```bash
cd terraform/examples/complete
terraform plan -out=services.tfplan
terraform show services.tfplan
terraform apply services.tfplan
```

Ambas regiones quedan *warm*: las dos corren Keycloak, aunque Route 53 entregue tráfico a una sola.

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

Exigen las dos tareas ECS en ejecución y los dos endpoints regionales saludables. Consultan AWS; no prueban por sí solos writer, peering, DNS, TLS ni RTO/RPO.

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

El plan hace exactamente dos cosas: promueve Aurora en la región destino y después mueve el health check de Route 53. **No hay gate posterior a la promoción**: DNS puede publicar el ALB destino mientras Keycloak todavía renueva DNS y conexiones al nuevo writer. Registrá cualquier `5xx`, fallo de login o intervalo de indisponibilidad.

Desde un cliente limpio: resolver `app.<dominio>`, entrar, y verificar que el usuario y el perfil de control siguen ahí. La primera operación confirmada cierra el cronómetro. Comparar timestamps antes y después para el RPO; si no se puede medir, declararlo **no medido**.

## 8. Failback

Recuperar la región original, confirmar writer y reader reales y la salud de ambos Keycloak, y ejecutar un switchover planificado inverso. Correr `terraform plan` después de cada promoción: el writer cambia fuera de Terraform.

## 9. Desmontar

Detener ambos servicios ECS y confirmar que no haya ejecuciones ARC activas. Conservar un snapshot manual si hay datos a retener. `deletion_protection` está en `true` por defecto: bajarlo a `false` en `terraform.tfvars` sólo cuando el borrado esté autorizado.

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
