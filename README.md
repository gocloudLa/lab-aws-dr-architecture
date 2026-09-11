# Disaster Recovery Regional en AWS

> Repositorio: `lab-aws-dr-architecture`

Lab de Disaster Recovery en AWS para AWS Community Day: recuperación regional de **Keycloak**
sobre **Aurora PostgreSQL Global Database**, con conmutación orquestada por **AWS Application
Recovery Controller (ARC) Region switch**.

El patrón es **pilot light regional**: una región sirve el tráfico con su ECS corriendo; la
otra tiene su clúster Aurora replicando pero el ECS en 0 tareas. Ante un DR, ARC promueve
Aurora en la región destino, escala su ECS y recién entonces conmuta el DNS público.

Regiones: **us-east-2 (Ohio)** primaria / **us-east-1 (Virginia)** secundaria.

## Cómo funciona, en tres líneas

1. Keycloak corre en ECS Fargate detrás de un ALB, contra el clúster Aurora **de su propia
   región** (no hay tráfico entre regiones, así que no hace falta peering).
2. Aurora Global Database replica de la región primaria a la secundaria de forma asíncrona.
3. Un plan de ARC hace, en orden estricto: promover Aurora → escalar el ECS destino → mover
   el DNS de `app.<dominio>` a la región destino.

## Orquestación

Todo se despliega con **Terragrunt** (que usa Terraform como binario por debajo), separado en
seis capas para evitar condiciones de carrera entre recursos. Un solo comando aplica el stack
completo respetando el orden de dependencias:

```
export PATH="$HOME/bin:$PATH"
make tg-apply
```

La operación de la demo (bootstrap del realm, switchover, failback) se maneja con targets
`make`. Ver la guía en [docs/demo.md](docs/demo.md).

## Estructura del repo

- `app/` — Imagen Docker de Keycloak (TLS a Aurora, health checks)
- `docs/` — Documentación: arquitectura, guía de la demo, diagramas
- `scripts/` — Scripts de operación (bootstrap, ARC, preflight, build-push)
- `terragrunt/` — Stack por capas: project (global, use2, use1) + workload
- `.docker/` — docker-compose para correr Keycloak local contra PostgreSQL
- `Makefile` — Targets de validación, despliegue y operación

## Documentación

| Documento | Contenido |
|---|---|
| [docs/demo.md](docs/demo.md) | Guía punta a punta: aplicar el stack, bootstrap del realm, ensayo de switchover y failback, con la referencia de comandos `make` |
| [docs/architecture.md](docs/architecture.md) | Diseño de la solución: pilot light regional, red, datos, ARC, decisiones y tradeoffs |
| [docs/diagrams/](docs/diagrams/) | Diagrama editable (`.drawio`) de la arquitectura completa |
| [terragrunt/README.md](terragrunt/README.md) | Por qué seis capas, el DAG, convenciones de naming, hostnames y state |
| [app/README.md](app/README.md) | La imagen de Keycloak: variables, TLS con RDS, endpoints de salud |

## Inicio rápido

Validación local, sin credenciales AWS ni crear nada:

```
make init      # baja wrappers y providers de todas las capas
make validate  # sintaxis de scripts, contratos estáticos y terragrunt hcl validate
make local-up  # Keycloak contra un PostgreSQL local (docker compose)
```

Despliegue y operación (requieren credenciales AWS activas):

```
make tg-apply                # aplicar el stack completo
make build-push TAG=demo-v1  # publicar la imagen en ambos ECR
make bootstrap               # crear el realm y usuario de demo

# Ensayar el switchover a Virginia y seguir la ejecución
make arc-start OPERATION=switchover TARGET_REGION=us-east-1
make arc-poll OPERATION=switchover EXECUTION_ID=<id>
```

`make help` lista todos los targets disponibles.

## Prerrequisitos

- Terragrunt v1.x, AWS CLI v2, Docker y `jq`.
- Una red AWS preexistente (VPC, subredes públicas/privadas/de base de datos y NAT) en ambas
  regiones, resuelta por tag `Name`.
- Una zona pública Route 53 con un certificado ACM que cubra `app.<dominio>` y los hostnames
  regionales, en cada región.
- Permisos sobre RDS, ECS, ECR, ELB, VPC, Route 53, IAM y ARC Region switch.
