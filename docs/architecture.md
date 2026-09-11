# Arquitectura

Recuperación regional de Keycloak sobre Aurora PostgreSQL Global Database, con un patrón **warm standby regional**: las dos regiones conservan su ECS con 1 tarea y su clúster Aurora replicando. La región activa sirve el tráfico; la región en espera usa `targetServerType=any` para aceptar el endpoint reader, pero no se considera apta para tráfico porque Aurora todavía no permite escrituras. ARC Region switch promueve Aurora, reafirma el ECS destino y recién entonces conmuta el DNS.

```mermaid
flowchart LR
  U[Usuario] --> D["Route 53 público<br/>app.dominio"]
  D -->|PRIMARY| A2[ALB Ohio]
  D -. SECONDARY .-> A1[ALB Virginia]
  A2 --> E2["ECS Keycloak Ohio<br/>activo · N tareas"]
  A1 -. "3 reafirma capacidad" .-> E1["ECS Keycloak Virginia<br/>warm · 1 tarea, sin tráfico"]
  E2 -->|JDBC TLS local| W[Aurora writer Ohio]
  E1 -->|JDBC TLS local| R[Aurora réplica Virginia]
  W == replicación asíncrona ==> R
  ARC[ARC Region switch] -. "1 Promover Aurora" .-> R
  ARC -. "2 Escalar ECS destino" .-> E1
  ARC -. "3 Route 53 health check" .-> D
```

El diagrama editable de toda la solución está en [diagrams](diagrams).

## Warm standby regional

Las dos regiones corren con la **misma configuración**: clúster Aurora replicando y ECS con 1 tarea (`desired_count=1`, autoscaling `min=max=1`). La región activa sirve tráfico normalmente. La región en espera mantiene su tarea Keycloak corriendo y su OIDC regional responde; `targetServerType=any` evita rechazar la conexión sólo por tratarse de un reader, pero no habilita las escrituras que Keycloak pueda necesitar.

Esta es una decisión de diseño explícita: se mantienen las dos regiones simétricas, pero la región reader no se publica ni se considera funcionalmente lista hasta la promoción. Consecuencias a decir en voz alta:

- El RTO no depende sólo de la promoción de Aurora y del DNS: tras promover, ARC reafirma la capacidad de la tarea de la región destino, que ya estaba corriendo. La tarea no hay que crearla desde 0; aun así hay que medir reconexiones y la primera escritura confirmada contra Aurora recién promovido.
- Se paga cómputo ECS de **ambas** regiones todo el tiempo, más el clúster Aurora replicando y el ALB. Es más caro que un pilot light, y es el trade-off aceptado del warm standby simétrico.
- Cada Keycloak conecta siempre al clúster Aurora de su **propia** región, nunca al de la otra: no hay ninguna carga que necesite alcanzar por PostgreSQL una VPC remota.

## Red

Cada región tiene su VPC con CIDR no superpuesto, dos AZ, subredes públicas para el ALB, privadas con salida por NAT para las tareas ECS, y subredes dedicadas para Aurora. **No hace falta peering ni Transit Gateway entre las dos VPC**: como ningún Keycloak conecta a Aurora en la región opuesta, no hay tráfico cruzado que rutear.

Aurora no tiene acceso público. Las tareas ECS corren en subredes privadas sin IP pública y su security group sólo acepta tráfico del ALB de su región. Los security groups de Aurora sólo permiten PostgreSQL desde los CIDR de las subredes de aplicación de **su propia** región.

## Datos

Aurora Global Database mantiene el writer inicial en Ohio y una réplica asíncrona en Virginia, con una instancia provisioned por región (`aurora_instance_class`, memory-optimized; Aurora Global Database no admite clases burstable como `db.t3`/`db.t4g`). Una instancia por clúster es una elección de demo y **no** equivale a alta disponibilidad completa dentro de una región.

`DB_HOST` es el endpoint del clúster Aurora **regional**, distinto en cada región (no el Global Writer Endpoint compartido). Mientras una región es secundaria, su endpoint local es de sólo lectura. `KC_DB_URL_PROPERTIES=?targetServerType=any` permite que el driver abra la conexión contra ese reader, pero cualquier operación que requiera escritura depende de que ARC promueva el clúster. Tras la promoción, el mismo hostname empieza a aceptar escrituras sin que Keycloak deba cambiar de `DB_HOST`. No hay RDS Proxy, CNAME de base de datos, Lambda de writer ni cambio de DNS privado.

## DNS y TLS

El driver JDBC conecta con el hostname real del clúster Aurora regional usando `sslmode=verify-full` y el bundle de CA de RDS como `sslrootcert`: se mantiene validación de cadena y de hostname. No se usa `sslmode=require` como sustituto.

El pool renueva conexiones (`KC_DB_POOL_MAX_LIFETIME=30s`) y la caché DNS de Java queda acotada (`-Dsun.net.inetaddr.ttl=5`); esto favorece la recuperación cuando el clúster local cambia de reader a writer.

`app.<dominio>` usa alias FAILOVER a los dos ALB con `evaluate_target_health=false`: sólo los health checks que genera ARC se asocian a esos registros, así el orden de la conmutación lo decide ARC y no Route 53. Los hostnames regionales (`app-use2.<dominio>`, `app-use1.<dominio>`) apuntan siempre a su propio ALB, para diagnóstico.

## Orquestación ARC

El plan de ARC Region switch tiene exactamente tres pasos, en orden estricto:

1. Promover Aurora Global Database hacia la región destino (`AuroraGlobalDatabase`).
2. Reafirmar la capacidad del ECS Keycloak de la región destino (`ECSServiceScaling`, `target_percent=100`). En warm standby ya hay una tarea corriendo; este paso espera la capacidad objetivo con Aurora ya promovido y escribible.
3. Activar el health check Route 53 del registro público para dirigir `app.<dominio>` al ALB destino (`Route53HealthCheck`).

`arc_aurora_behavior` define el modo del paso 1: `switchoverOnly` para una operación planificada, `failover` cuando se acepta posible pérdida. No hay gates Lambda ni gate OIDC.

El paso 2 sí es un gate real: ARC espera a que el ECS destino alcance la capacidad pedida (o el timeout) antes de pasar al paso 3, así que el DNS no se mueve hacia un backend sin tareas corriendo. No hay comprobación de que Keycloak ya pasó su health check de aplicación (`/health/ready`) más allá de lo que el propio ECS/ALB reportan; ese período de arranque hay que medirlo y reportarlo en el ensayo. La continuidad de sesión de Keycloak no está garantizada; se admite re-login.

### La región saliente no se apaga automáticamente (y por qué)

Tras un switchover, la región que queda como secundaria mantiene el `desired_count` con el que ARC la dejó (típicamente 1). El plan **no** la vuelve a 0 por sí solo, y esto no es un descuido de configuración sino un límite del servicio: **un plan de tipo `activePassive` no admite workflows con `workflow_target_action = "deactivate"`**. La API los rechaza explícitamente al crear/actualizar el plan:

```
ValidationException: activePassive plans must not specify target action 'deactivate'.
```

Sólo se permiten workflows `activate` (uno por región). En consecuencia, ARC no ejecuta ninguna acción sobre la región que se desactiva. Con el patrón warm standby esto es indistinto: la región saliente conserva 1 tarea y su Aurora pasa a reader, que es su estado normal de espera sin tráfico. Si en cambio se quisiera apagarla del todo, habría que bajarla a 0 fuera del plan:

```bash
aws ecs update-service --region <saliente> --cluster <cluster> --service <service> --desired-count 0
```

Se probó agregar los workflows `deactivate` (con un paso `ECSServiceScaling` a `target_percent = 0`) y AWS los rechazó con el error de arriba. Una alternativa sería un paso `custom_action_lambda` dentro del workflow `activate`, pero reintroduce una Lambda que el diseño busca evitar.

### Comportamiento de la región en espera

Las dos regiones conservan 1 tarea (warm standby simétrico). Keycloak establece por defecto `targetServerType=primary`; antes de sobrescribirlo, el reader era rechazado durante la apertura de la conexión y se observaba:

```
ERROR: Could not find a server with specified targetServerType: primary
ERROR: Failed to obtain JDBC connection
ERROR: Failed to start server in (production) mode
```

La configuración actual corrige esa comprobación en ambas task definitions con `targetServerType=any`. Esto permite conectarse al reader, pero no convierte a Aurora en escribible ni demuestra que todas las operaciones de Keycloak funcionen en espera. Por eso los prechecks exigen que ambas tareas estén corriendo y que su OIDC regional responda; aun así reservan la validación funcional de escritura para la región writer efectiva. Cuando ARC promueve Aurora, el mismo endpoint local pasa a aceptar escrituras.

El paso `ECSServiceScaling` del plan sigue siendo útil: tras la promoción, reafirma la capacidad de la región destino y actúa como gate de capacidad antes de conmutar el DNS. No reemplaza una comprobación funcional de Keycloak; esa diferencia debe medirse durante el ensayo.

> Alternativa no elegida: un **pilot light** (región en espera en `desired_count=0`) ahorra el cómputo ECS de la región pasiva, pero rompe la simetría entre regiones. Se descartó a favor del warm standby.

## Estructura del código

La orquestación es Terragrunt por capas:

```
terragrunt/                          # orquestación por capas
├── root.hcl                         # backend local, un state por capa
├── project/
│   ├── drarch-global/laboratory/    # aws_rds_global_cluster y credenciales
│   ├── drarch-use2/laboratory/      # Ohio: ECR, Aurora, ALB, clúster ECS
│   └── drarch-use1/laboratory/      # Virginia: ídem
└── workload/
    ├── drarch-use2/laboratory/      # Ohio: ECS service
    ├── drarch-use1/laboratory/      # Virginia: ECS service (warm, misma config que Ohio)
    └── drarch-arc/laboratory/       # plan de ARC, rol IAM y DNS failover
```

Las capas no son una preferencia estética: los wrappers resuelven ALB, target groups y
clúster ECS con data sources internos cuyo `for_each`/`count` depende de recursos que no
existen todavía, así que un único state no puede expandir el grafo y el plan falla con
`Invalid for_each argument`. Separado en capas, cada una planifica cuando lo de abajo ya
existe. Detalle y DAG en [terragrunt/README.md](../terragrunt/README.md).

La red (VPC, subredes, NAT), la zona Route 53 y los certificados ACM regionales se asumen
preexistentes y se resuelven por tags/data sources. En la cuenta laboratorio los nombres vienen
de `metadata` (`dmc-lab`, `lab.democorp.cloud` y sus subredes `public*`, `private*`, `db*`).
Para reutilizar la demo en otra cuenta hay que crear esa base y adaptar `metadata.tf` y los data
sources al dominio y tagging propios; Terraform no la aprovisiona. No hace falta peering ni
conectividad interregional: cada Keycloak conecta al clúster Aurora de su propia región.

Todo se compone con los wrappers de la [Standard Platform de gocloudLa](https://github.com/gocloudLa): `wrapper-rds-aurora`, `wrapper-alb`, `wrapper-ecs`, `wrapper-ecs-service` y `wrapper-ecr`. No se mezclan orígenes de módulos.

Quedan como `resource` suelto, y sólo porque no existe wrapper equivalente:

| Recurso | Por qué |
|---|---|
| `aws_rds_global_cluster` | Es el recurso que define la demo; ningún wrapper lo cubre |
| `aws_arcregionswitch_plan` y su rol IAM | ARC Region switch no tiene wrapper |
| `aws_route53_record` FAILOVER | Deben asociarse a los health checks que genera ARC |
| `data.aws_rds_cluster` (en la capa `project` regional) | El wrapper de Aurora no publica el endpoint del clúster regional como output |

### Providers por región, no el argumento `region`

El provider AWS v6 permite fijar `region` recurso por recurso y así evitar aliases. Acá no se puede: los wrappers resuelven VPC, subredes, security group por defecto, clúster ECS y listener del ALB con **data sources internos que no reciben `region`**. Si se fijara `region` sólo en los recursos, esos `data` seguirían resolviendo contra la región del provider y quedarían apuntando a la red equivocada.

De los recursos que sí declaramos, `aws_rds_global_cluster` y `aws_arcregionswitch_plan` aceptan `region`; `aws_route53_record`, `aws_iam_role` y `aws_iam_role_policy` no lo tienen porque son servicios globales. Cada capa regional corre con el provider de su propia región, así que no hace falta duplicar `region` recurso por recurso.

### Dependencias

Dentro de cada capa, casi todas son implícitas, por referencia a atributos reales:

- El ALB y Aurora reciben **IDs de subred**, no patrones de tag.
- `wrapper-alb` no publica el nombre del ALB, así que se deriva del ARN del listener 443. Además de dar el nombre exacto, obliga a que el listener exista antes de que `wrapper-ecs-service` lo busque.

Entre capas, el orden lo garantiza el DAG de Terragrunt (`dependency`/`dependencies`), no
`depends_on`: cuando una capa planifica, los recursos de las capas de abajo ya existen y se
resuelven con data sources o llegan como outputs concretos. Ése es justamente el problema que
la separación en capas elimina.

## Interfaces

| Variable | Propósito |
|---|---|
| `DB_HOST` | Endpoint del clúster Aurora **de esta región** (no el Global Writer Endpoint compartido) |
| `DB_PORT=5432`, `DB_NAME` | Conexión PostgreSQL |
| `sslmode=verify-full`, `sslrootcert` | TLS local con hostname y CA de RDS |
| `KC_DB_USERNAME`, `KC_DB_PASSWORD` | Parámetro SSM cifrado, inyectado como secreto de la task |
| `KC_BOOTSTRAP_ADMIN_USERNAME`, `KC_BOOTSTRAP_ADMIN_PASSWORD` | Administración inicial, también como secreto |
| `KC_HOSTNAME` | Nombre público canónico de Keycloak |
| `:9000/health/live`, `:9000/health/ready` | Liveness y readiness regionales |

El output `global_writer_endpoint` del stack sigue existiendo (agrupa los dos clústeres regionales bajo el `aws_rds_global_cluster`), pero es sólo diagnóstico: ningún `DB_HOST` de Keycloak lo usa.

## Fuentes

- [Conexión a una Aurora Global Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-connecting.html)
- [SSL para RDS PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.SSL.html)
- [ARC Region switch: bloque Aurora](https://docs.aws.amazon.com/r53recovery/latest/dg/aurora-global-database-block.html)
- [ARC Region switch: bloque Route 53](https://docs.aws.amazon.com/r53recovery/latest/dg/route53-health-check-block.html)
- [Health checks de Keycloak](https://www.keycloak.org/observability/health)
