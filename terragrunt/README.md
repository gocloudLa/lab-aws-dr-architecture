# Stack Terragrunt, por capas

Orquestación por capas al estilo de la Standard Platform (`<layer>/<project>/<environment>`),
con backend **local**: este lab no usa un bucket compartido de state remoto.

## Por qué capas y no un único root module

Los wrappers de la Standard Platform resuelven ALB, target groups, clúster ECS y secretos
con **data sources internos** cuyo `for_each`/`count` depende de valores que sólo existen
después de crear la capa anterior. Con todo en un solo state, Terraform no puede expandir
ese grafo y el plan falla antes de empezar:

```
Error: Invalid for_each argument
  local.create_target_groups will be known only after apply
Error: Invalid count argument
  The "count" value depends on resource attributes that cannot be determined until apply
```

Ese error no se arregla reordenando código: es una limitación de un único grafo. Separando
en capas, cada una planifica cuando los recursos de las capas de abajo ya existen y sus
valores son concretos. Terragrunt aporta el orden (DAG) y el paso de outputs entre capas.

## Capas

| Capa | Qué crea | Por qué es capa propia |
|---|---|---|
| `project/drarch-global/laboratory` | `aws_rds_global_cluster`, contraseñas compartidas | Su identificador alimenta el `for_each` del wrapper de Aurora; creado antes, ya es concreto |
| `project/drarch-use2/laboratory` | Ohio: ECR, Aurora, ALB, clúster ECS | El clúster regional necesita el Global Database ya existente |
| `project/drarch-use1/laboratory` | Virginia: ídem | Un clúster secundario sólo puede unirse cuando el primario existe |
| `workload/drarch-use2/laboratory` | Ohio: ECS service Keycloak | Necesita el listener del ALB, el ECR y el endpoint de Aurora ya creados |
| `workload/drarch-use1/laboratory` | Virginia: ECS service (warm, 1 tarea) | Misma config que Ohio; conecta al reader, pero recibe tráfico sólo después de la promoción |
| `workload/drarch-arc/laboratory` | Plan de ARC, rol IAM, registros FAILOVER | Referencia ARNs de Aurora y de los servicios ECS de las dos regiones |

DAG resultante (`make tg-graph`). `make tg-apply` inserta la publicación de la imagen entre
las capas `project` y `workload`:

```
global ──> project use2 ──> project use1
                     │             │
                     └──> build-push ──┬─> workload use2 ──┐
                                      └─> workload use1 ──┴─> arc
```

## Uso

```bash
make tg-graph     # ver el DAG
make tg-plan      # plan de todas las capas
make tg-apply IMAGE_TAG=demo-v1  # project -> imagen ECR -> workload
make tg-output    # outputs agregados que consumen los scripts
```

Un `tg-plan` **desde cero** sólo resuelve las tres capas `project`. Las capas `workload`
leen el ALB y el clúster ECS con data sources, que existen recién después del apply de las
capas de abajo: es el comportamiento esperado, no un error de configuración.

`tg-apply` es reanudable: si se corta a mitad (por ejemplo, porque expiran las credenciales),
el state de cada capa ya aplicada persiste y basta con volver a correrlo con el mismo
`IMAGE_TAG`. Si el tag ya existe con el mismo digest en ambos ECR, la etapa de publicación lo
reutiliza. Para desplegar cambios de la aplicación se debe usar un tag nuevo.

Los targets `make tg-apply-project` y `make tg-apply-workload IMAGE_TAG=<tag>` existen sólo
para recuperar una ejecución interrumpida. No publicar una imagen con `build-push` y aplicar
solamente `project`: los servicios ECS se crean o actualizan en la etapa `workload`.

## Convenciones heredadas de la Standard Platform

- `metadata.key.company = "dmc"` y `env = "lab"` hacen que `common_name_prefix` sea `dmc-lab`,
  que es el tag `Name` real de la VPC. Así los wrappers aciertan con sus defaults y no hay
  que pasarles `vpc_name`.
- `common_name` es `dmc-lab-drarch`; los recursos regionales se sufijan con `use2` / `use1`.
- `conditions.tf` deriva `zone_public` del entorno: para `lab` es `lab.democorp.cloud`.
- El certificado ACM se resuelve por data source sobre esa zona, en cada región.

## Hostnames

| Hostname | Qué es |
|---|---|
| `app.lab.democorp.cloud` | Público, conmuta entre regiones (registros FAILOVER + health checks de ARC) |
| `app-use2.lab.democorp.cloud` | Diagnóstico, siempre el ALB de Ohio |
| `app-use1.lab.democorp.cloud` | Diagnóstico, siempre el ALB de Virginia |

Los regionales usan **un solo label** (`app-use2`, no `use2.app`) porque el certificado es
`*.lab.democorp.cloud` y el wildcard de ACM cubre exactamente un nivel.

## State

`terragrunt/.tfstate/<layer>/<project>/<environment>/terraform.tfstate`, fuera de
`.terragrunt-cache` para que persista. No se versiona.
