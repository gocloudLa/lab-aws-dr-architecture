# Guía de la demo, punta a punta

La demo se orquesta con **Terragrunt** sobre una red AWS ya existente (VPC, subredes y NAT).
Todo el ciclo (bootstrap del realm, switchover y failback) se opera con targets `make`.

## Prerrequisitos

- Terragrunt v1.x (usa Terraform como binario por debajo), AWS CLI v2, Docker y `jq`.
- Una cuenta AWS con permisos sobre RDS, ECS, ECR, ELB, VPC, Route 53, IAM y ARC Region switch.
- Una zona pública Route 53 con un dominio propio.
- Dos certificados ACM, uno por región (`us-east-2` y `us-east-1`), que cubran `app.<dominio>`
  y los hostnames regionales `app-use2.<dominio>` / `app-use1.<dominio>`. Un wildcard
  `*.<dominio>` cubre los tres (es un solo label bajo el dominio).
- Credenciales AWS activas exportadas en la terminal antes de cada operación contra AWS.

## Orquestación por capas

El stack se separa en **seis capas** bajo `terragrunt/`, siguiendo la convención
`<layer>/<project>/<environment>`. Cada capa existe para romper una dependencia que un único
state no puede resolver (los wrappers resuelven ALB, target groups y clúster ECS con data
sources internos cuyo `for_each`/`count` no se puede expandir hasta que existan los recursos
de la capa de abajo). Ver [terragrunt/README.md](../terragrunt/README.md) para el DAG completo.

```
project/drarch-global/laboratory    # aws_rds_global_cluster + credenciales compartidas
project/drarch-use2/laboratory       # Ohio: ECR, Aurora, ALB, clúster ECS
project/drarch-use1/laboratory       # Virginia: ídem
workload/drarch-use2/laboratory      # Ohio: ECS service
workload/drarch-use1/laboratory      # Virginia: ECS service (warm, misma config que Ohio)
workload/drarch-arc/laboratory       # plan de ARC, rol IAM y registros Route 53 FAILOVER
```

Los scripts que operan AWS leen, mediante `lib.sh`, los outputs de las seis capas y los
agregan en un único contrato JSON. `bootstrap.sh` y `write-probe.sh` son la excepción: operan
contra `KEYCLOAK_URL` y las credenciales exportadas por el operador.

La red se resuelve por tag `Name`, no por ID: la VPC debe tener subredes públicas (ALB),
privadas con salida por NAT (ECS) y de base de datos, más un security group por defecto
etiquetado, con el prefijo de nombre que fija `metadata` en cada capa. **No hace falta peering
ni conectividad interregional**: cada Keycloak conecta siempre al clúster Aurora de su propia
región (patrón warm standby, ver [architecture.md](architecture.md)).

## 1. Aplicar el stack

Terragrunt v1 quedó instalado en `~/bin`; asegurate de tenerlo en el `PATH`:

```bash
export PATH="$HOME/bin:$PATH"
make tg-apply     # un comando, respeta el DAG (~20 min; Aurora domina, ~7 min por región)
```

Es reanudable: si las credenciales expiran a mitad, el state de cada capa ya aplicada
persiste y alcanza con volver a correrlo. Las dos regiones arrancan con `ecs_desired_count = 1`
(warm standby). La tarea secundaria puede conectar al endpoint reader por
`targetServerType=any`, pero no se considera apta para tráfico hasta que ARC promueva su
Aurora y habilite escrituras.

Notas de configuración de este lab, ya fijadas en el código:

- **Aurora provisioned `db.r6g.large`**: Global Database no admite clases burstable
  (`db.t3`/`db.t4g`); ésta es la memory-optimized más chica disponible en ambas regiones.
- **Engine `16.14`**: la `16.6` fue deprecada en RDS.
- **Container Insights deshabilitado** en ambos clústeres ECS (no se necesita esa telemetría
  para el lab).

## 2. Publicar la imagen en ambas regiones

Una sola imagen, el mismo tag en los dos ECR. Los repositorios son inmutables: un tag no se
repisa.

```bash
make build-push TAG=demo-v1
```

## 3. Verificar el estado warm de las dos regiones

Las dos regiones arrancan con su ECS service en 1 tarea (**warm standby**, misma config). La
primaria inicial (Ohio) debe correr sana. La secundaria inicial (Virginia) conserva su tarea
programada y el driver acepta el reader por `targetServerType=any`; eso no habilita escrituras
ni garantiza que Keycloak esté listo para servir tráfico. La promoción de Aurora durante la
conmutación habilita la operación completa en Virginia (ver paso 6).

## 4. Cargar el realm de demo

Las credenciales del admin de Keycloak las genera la capa global y quedan como outputs
sensibles. El bootstrap crea el realm `community-day` y el usuario de demo, de forma
idempotente:

```bash
GLOBAL=terragrunt/project/drarch-global/laboratory

export KEYCLOAK_URL="https://app.<dominio>"
export KC_BOOTSTRAP_ADMIN_USERNAME=$(cd "$GLOBAL" && terragrunt output -raw keycloak_bootstrap_admin_username)
export KC_BOOTSTRAP_ADMIN_PASSWORD=$(cd "$GLOBAL" && terragrunt output -raw keycloak_bootstrap_admin_password)
export DEMO_PASSWORD="<una contraseña para el usuario de demo>"

make bootstrap
```

Verificación rápida: `GET $KEYCLOAK_URL/realms/community-day` debe responder `200`, y un
login del usuario de demo contra ese realm también `200` (confirma que la escritura previa
se persistió en Aurora).

## 5. Preflight

```bash
make preflight
make demo-precheck
```

Consultan Aurora para identificar el **writer actual**, incluso después de un switchover. En
esa región exigen la tarea ECS en ejecución y el endpoint regional OIDC saludable. De la
región reader sólo validan que el servicio conserve capacidad programada (`desiredCount > 0`):
un `runningCount` menor o la falta de OIDC no bloquean el preflight mientras siga siendo
reader. También comprueban la evaluación del plan ARC; no miden por sí solos RTO/RPO ni una
operación funcional de escritura en la región warm.

## 6. Ensayo de conmutación (switchover)

Antes de arrancar: registrar commit, tag, hora UTC, writer actual y los dos hostnames
regionales. Crear un usuario en Admin Console y actualizar un perfil en Account Console, o
usar `make write-probe`, para tener un dato de control.

```bash
# 1. (Opcional) Dejar un dato de control escrito contra el writer actual
make write-probe

# 2. (Opcional) Simular la caída de la aplicación en la región activa
make fault-stop REGION=us-east-2

# 3. Conmutar. switchover no espera pérdida; failover la acepta explícitamente.
make arc-start OPERATION=switchover TARGET_REGION=us-east-1
# ACCEPT_DATA_LOSS=yes make arc-start OPERATION=failover TARGET_REGION=us-east-1

# 4. Seguir la ejecución hasta que complete (usar el executionId que devolvió arc-start)
make arc-poll OPERATION=switchover EXECUTION_ID=us-east-1/xxxxxxxxxxxxxxxx
```

`fault-stop` no inicia ARC ni es obligatorio para un switchover. Se usa sólo cuando se quiere
demostrar una caída de la capa ECS; para una conmutación planificada se puede ejecutar
`arc-start` directamente.

El plan del lab está configurado inicialmente con `arc_aurora_behavior = "switchoverOnly"`.
Para ensayar `OPERATION=failover`, primero hay que cambiarlo a `"failover"`, aplicar la capa
ARC y recién entonces ejecutar el comando con `ACCEPT_DATA_LOSS=yes`; el script rechaza un
failover si el comportamiento aplicado no coincide.

`arc-start` es asíncrono: `start-plan-execution` inicia la ejecución en el servicio y
devuelve el `executionId` de inmediato. Aunque el comando local se corte (por timeout o por
credenciales), la ejecución sigue en AWS; en ese caso, obtené el id con
`aws arc-region-switch list-plan-executions --region <TARGET_REGION> --plan-arn <arn>` y
seguí con `make arc-poll`. Iniciar un segundo `arc-start` mientras hay una ejecución en curso
falla con `There is already an execution ongoing`: es la misma conmutación, no un error.

El plan hace exactamente tres cosas, en orden estricto: promueve Aurora en la región destino,
reafirma el ECS de esa región (warm standby: ya tenía capacidad programada, pero recién ahora
su clúster local permite escrituras), y por último mueve el health check de Route 53. El
paso de ECS sí es un gate: ARC espera a que la capacidad pedida esté corriendo (o el timeout)
antes de tocar el DNS, así que Route 53 no publica un ALB sin backend. No hay, en cambio,
comprobación de que Keycloak ya pasó su propio health check de aplicación más allá de lo que
reporta el ECS. Registrá cualquier `5xx`, fallo de login o intervalo de indisponibilidad,
incluido el tiempo de arranque de Keycloak en la región destino.

Desde un cliente limpio: resolver `app.<dominio>`, entrar, y verificar que el usuario y el
perfil de control siguen ahí. La primera operación confirmada cierra el cronómetro. Comparar
timestamps antes y después para el RPO; si no se puede medir, declararlo **no medido**.

### Referencia rápida: todos los comandos `make` del ensayo

En orden, desde el stack ya aplicado (`make tg-apply`) con la imagen publicada:

| Paso | Comando `make` | Qué hace |
|---|---|---|
| Publicar imagen | `make build-push TAG=demo-v1` | Construye una imagen y la sube al ECR de ambas regiones |
| Cargar realm demo | `make bootstrap` | Crea el realm `community-day` y el usuario de demo (idempotente) |
| Preflight | `make preflight` | Detecta el writer actual; valida allí ECS/OIDC y exige capacidad programada en la reader |
| Precheck | `make demo-precheck` | Chequeos adicionales de estado previos a la conmutación |
| Dato de control | `make write-probe` | Escribe un registro de control contra el writer actual |
| Simular caída | `make fault-stop REGION=us-east-2` | Baja el ECS de la región activa para forzar el escenario |
| Restaurar caída | `make fault-restore REGION=us-east-2` | Revierte el `fault-stop` |
| **Iniciar switchover** | `make arc-start OPERATION=switchover TARGET_REGION=us-east-1` | Dispara el plan ARC hacia la región destino; devuelve `executionId` |
| **Seguir switchover** | `make arc-poll OPERATION=switchover EXECUTION_ID=<id>` | Sigue la ejecución hasta `completed` |
| Failover (con pérdida) | `ACCEPT_DATA_LOSS=yes make arc-start OPERATION=failover TARGET_REGION=us-east-1` | Igual que switchover pero acepta posible pérdida de datos |

Requisitos previos comunes: credenciales AWS activas en la terminal y `terragrunt` en el
`PATH`. `bootstrap`, `demo-precheck` y `write-probe` necesitan `KEYCLOAK_URL`; los dos scripts
que escriben también requieren `KC_BOOTSTRAP_ADMIN_USERNAME` y
`KC_BOOTSTRAP_ADMIN_PASSWORD`, y `bootstrap` requiere `DEMO_PASSWORD` (ver paso 4).

## 7. Failback (switchover inverso)

El mismo par de comandos, invirtiendo la región destino, devuelve el tráfico a la región
original:

```bash
make arc-start OPERATION=switchover TARGET_REGION=us-east-2
make arc-poll OPERATION=switchover EXECUTION_ID=us-east-2/xxxxxxxxxxxxxxxx
```

Validar después: el writer de Aurora volvió a la región original, su ECS corre, y
`app.<dominio>` resuelve al ALB de esa región.

La región que queda en espera sigue en 1 tarea: el plan de ARC sólo escala la región que
activa, no apaga la saliente. Con warm standby eso es el comportamiento esperado — la saliente
vuelve a su estado de espera con capacidad programada y Aurora reader. Aunque
`targetServerType=any` permita abrir la conexión, no se la considera apta para tráfico mientras
no pueda escribir. Si excepcionalmente quisieras apagarla del todo, bajála a mano con
`aws ecs update-service --region <saliente> --cluster <cluster> --service <service> --desired-count 0`;
`desired_count` está en `ignore_changes`, así que un `make tg-apply` posterior no lo pisa.

## 8. Desmontar

Detener ambos servicios ECS (`aws ecs update-service --desired-count 0` en las dos regiones) y
confirmar que no haya ejecuciones ARC activas. Conservar un snapshot manual si hay datos a
retener. En este lab `deletion_protection = false` y se omite el snapshot final; revisar y
cambiar esos valores antes de destruir si hay datos que deban conservarse.

```bash
terragrunt run --all destroy --non-interactive --working-dir terragrunt
```

Si AWS rechaza el orden de borrado, parar y revisar el estado real; no forzar sobre una
topología sin revisar.

## Validación local

Sin credenciales AWS y sin crear nada:

```bash
make init       # baja wrappers y providers de todas las capas
make validate   # sintaxis de scripts, contratos estáticos y terragrunt hcl validate
```

`make validate` no prueba Aurora, ARC, Route 53, TLS contra RDS, cuotas, permisos ni RTO/RPO.
Los parámetros de los wrappers son mapas de tipo `any`: la validación no verifica sus claves.
La única prueba real es el ensayo en AWS.
