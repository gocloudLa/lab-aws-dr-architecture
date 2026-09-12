# Disaster Recovery Regional en AWS

> Repositorio: `lab-aws-dr-architecture`

Lab de Disaster Recovery en AWS para AWS Community Day: recuperación regional de **Keycloak**
sobre **Aurora PostgreSQL Global Database**, con conmutación orquestada por **AWS Application
Recovery Controller (ARC) Region switch**.

El patrón es **warm standby regional**: las dos regiones configuran su ECS con 1 tarea deseada y
su Aurora replicando. En la región en espera Keycloak corre sano contra su Aurora reader porque
el clúster tiene **write forwarding**: las escrituras que necesita para arrancar y mantenerse
listo viajan al writer por el canal interno de Aurora. La región no recibe tráfico hasta que
ARC promueve su Aurora, reafirma su ECS y recién entonces conmuta el DNS público.

Regiones: **us-east-2 (Ohio)** primaria / **us-east-1 (Virginia)** secundaria.

## Cómo funciona, en tres líneas

1. Keycloak corre en ECS Fargate detrás de un ALB, contra el clúster Aurora **de su propia
   región** (no hay tráfico entre regiones, así que no hace falta peering).
2. Aurora Global Database replica de la región primaria a la secundaria de forma asíncrona.
3. Un plan de ARC hace, en orden estricto: promover Aurora → escalar el ECS destino → mover
   el DNS de `app.<dominio>` a la región destino.

## Orquestación

Todo se despliega con **Terragrunt** (que usa Terraform como binario por debajo), separado en
seis capas para evitar condiciones de carrera entre recursos. `make` aplica primero las capas
`project`, publica la imagen en ambos ECR y después aplica las capas `workload`:

```
export PATH="$HOME/bin:$PATH"
make tg-apply IMAGE_TAG=demo-v1
```

La operación de la demo (bootstrap del realm, switchover, failback) se maneja con targets
`make`. Ver la guía en [docs/demo.md](docs/demo.md).

## Estructura del repo

- `app/` — Imagen Docker de Keycloak (TLS a Aurora, health checks)
- `docs/` — Documentación: arquitectura, guía de la demo, diagramas
- `scripts/` — Scripts de operación (bootstrap, demo-precheck, ARC y build-push)
- `terragrunt/` — Stack por capas: project (global, use2, use1) + workload
- `Makefile` — Targets de validación, despliegue y operación

## Documentación

| Documento | Contenido |
|---|---|
| [docs/demo.md](docs/demo.md) | Guía punta a punta: aplicar el stack, bootstrap del realm, ensayo de switchover y failback, con la referencia de comandos `make` |
| [docs/architecture.md](docs/architecture.md) | Diseño de la solución: warm standby regional, red, datos, ARC, decisiones y tradeoffs |
| [docs/diagrams/](docs/diagrams/) | Diagrama editable (`.drawio`) de la arquitectura completa |
| [terragrunt/README.md](terragrunt/README.md) | Por qué seis capas, el DAG, convenciones de naming, hostnames y state |
| [app/README.md](app/README.md) | La imagen de Keycloak: variables, TLS con RDS, endpoints de salud |

## Inicio rápido

Validación local, sin credenciales AWS ni crear nada:

```
make init      # baja wrappers y providers de todas las capas
make validate  # sintaxis de scripts, contratos estáticos y terragrunt hcl validate
```

Despliegue y operación (requieren credenciales AWS activas):

```
make tg-apply IMAGE_TAG=demo-v1  # infraestructura, imagen y workloads
make build-push TAG=demo-v1      # publicación manual opcional
make bootstrap               # crear el realm y usuario de demo

# Ensayar el switchover a Virginia y seguir la ejecución
make arc-start OPERATION=switchover TARGET_REGION=us-east-1
make arc-poll OPERATION=switchover EXECUTION_ID=<id>
```

`make help` lista todos los targets disponibles.

Para desplegar un cambio de la aplicación, usar un tag nuevo, por ejemplo
`make tg-apply IMAGE_TAG=demo-v2`. Ejecutar sólo `build-push` publica una imagen, pero no
actualiza la task definition de ECS; el despliegue completo lo hace `tg-apply`.

## Prerrequisitos

- Terragrunt v1.x, AWS CLI v2, Docker y `jq`.
- La cuenta laboratorio ya aporta la red y certificados que el código descubre por data source:
  VPC `dmc-lab`, subredes `dmc-lab-public*`, `dmc-lab-private*`, `dmc-lab-db*`, zona
  `lab.democorp.cloud` y certificados ACM regionales.
- En otra cuenta, crear previamente una VPC por región con subredes públicas, privadas con NAT
  y de base de datos; la zona Route 53 y certificados ACM por región. Luego adaptar
  `metadata.tf` y los data sources al dominio y tagging propios. El stack no crea esa base.
- Permisos sobre RDS, ECS, ECR, ELB, VPC, Route 53, IAM y ARC Region switch.
