TG_DIR ?= terragrunt
IMAGE_TAG ?= demo-v1

.DEFAULT_GOAL := help

.PHONY: help init validate test-local build-push bootstrap \
	demo-precheck write-probe arc-start arc-poll \
	tg-init tg-validate tg-fmt tg-graph tg-plan tg-apply tg-apply-project \
	tg-apply-workload tg-output tg-destroy

# Muestra los comandos disponibles, agrupados por etapa de la demo.
help:
	@echo "Validación y entorno local:"
	@echo "  make init          # baja wrappers y providers de todas las capas"
	@echo "  make validate      # sintaxis de scripts y contratos estáticos"
	@echo "  make test-local"
	@echo "Stack Terragrunt (por capas, TG_DIR=$(TG_DIR)):"
	@echo "  make tg-graph      # DAG de dependencias entre capas"
	@echo "  make tg-plan       # plan de todas las capas"
	@echo "  make tg-apply IMAGE_TAG=$(IMAGE_TAG)  # project -> imagen ECR -> workload"
	@echo "  make tg-apply-project                 # sólo infraestructura base (recuperación)"
	@echo "  make tg-apply-workload IMAGE_TAG=$(IMAGE_TAG)  # sólo ECS/ARC (recuperación)"
	@echo "  make tg-output     # outputs agregados que consumen los scripts"
	@echo "  make tg-destroy    # destruye todo el stack en orden inverso de dependencias"
	@echo "Operación de la demo:"
	@echo "  make build-push TAG=demo-v1"
	@echo "  make bootstrap"
	@echo "  make demo-precheck"
	@echo "  make write-probe"
	@echo "  make arc-start OPERATION=switchover TARGET_REGION=us-east-1"
	@echo "  make arc-poll OPERATION=switchover EXECUTION_ID=<id>"

# ---------------------------------------------------------------------------
# Validación local (no requiere credenciales AWS)
# ---------------------------------------------------------------------------

# Inicializa Terragrunt y sus dependencias; es un alias de tg-init.
init: tg-init

# Ejecuta los tests locales y valida el HCL después de formatearlo.
validate: test-local tg-validate

# Revisa sintaxis Bash y contratos sin crear ni modificar recursos en AWS.
test-local:
	@set -e; for script in scripts/*.sh scripts/tests/*.sh app/entrypoint.sh; do bash -n "$$script"; done
	scripts/tests/arc-contracts.sh
	scripts/tests/static-contracts.sh

# ---------------------------------------------------------------------------
# Terragrunt: orquestación por capas
# ---------------------------------------------------------------------------

# Cada capa resuelve sus propios providers; no configura backend remoto (state local).
# Descarga/inicializa providers y módulos en todas las capas de Terragrunt.
tg-init:
	terragrunt run --all init --non-interactive --working-dir $(TG_DIR)

# Normaliza el formato de todos los archivos HCL de Terragrunt.
tg-fmt:
	terragrunt hcl fmt --working-dir $(TG_DIR)

# Comprueba la sintaxis y referencias HCL de las capas ya formateadas.
tg-validate: tg-fmt
	terragrunt hcl validate --working-dir $(TG_DIR)

# Imprime el grafo de dependencias que determina el orden de las capas.
tg-graph:
	terragrunt dag graph --working-dir $(TG_DIR)

# Un plan desde cero sólo resuelve las capas project: las workload leen el ALB y el
# clúster ECS con data sources, que existen recién después del apply de las capas de abajo.
# Calcula cambios potenciales; no crea ni cambia recursos.
tg-plan:
	terragrunt run --all plan --non-interactive --working-dir $(TG_DIR)

# Aplica primero project, publica la imagen y recién después crea los workloads.
# Si el tag ya existe con el mismo digest en ambos ECR, lo reutiliza para permitir reapplies.
tg-apply:
	@test -n "$(IMAGE_TAG)" || { echo "Falta IMAGE_TAG. Uso: make tg-apply IMAGE_TAG=demo-v1" >&2; exit 64; }
	$(MAKE) tg-apply-project
	ALLOW_EXISTING_TAG=yes $(MAKE) build-push TAG="$(IMAGE_TAG)"
	$(MAKE) tg-apply-workload IMAGE_TAG="$(IMAGE_TAG)"

# Crea la infraestructura base, incluidos los dos repositorios ECR. Útil para reanudar un fallo.
tg-apply-project:
	terragrunt run --all apply --non-interactive --working-dir $(TG_DIR)/project

# Crea los servicios ECS y ARC usando exactamente la imagen publicada en la etapa anterior.
# Usar sólo después de build-push; es útil para reanudar un fallo de la tercera etapa.
tg-apply-workload:
	IMAGE_TAG="$(IMAGE_TAG)" terragrunt run --all apply --non-interactive --working-dir $(TG_DIR)/workload

# Muestra los outputs que usan los scripts operativos de la demo.
tg-output:
	scripts/show-outputs.sh

# Destruye el stack completo. Terragrunt recorre el DAG en orden inverso (workload antes que
# project), así que un solo comando basta. Aurora tarda varios minutos por región; si se corta
# por credenciales expiradas, es reanudable (el state de cada capa ya destruida persiste).
# Requiere deletion_protection = false en las capas de Aurora (ya es el default del lab).
# Elimina la infraestructura del laboratorio, en orden inverso al aprovisionamiento.
tg-destroy:
	terragrunt run --all destroy --non-interactive --working-dir $(TG_DIR)

# ---------------------------------------------------------------------------
# Operación de la demo
# ---------------------------------------------------------------------------

# Construye una sola imagen y publica el mismo contenido en ambos ECR regionales.
build-push:
	@test -n "$(TAG)" || { echo "Falta TAG. Uso: make build-push TAG=demo-v1" >&2; exit 64; }
	scripts/build-push.sh "$(TAG)"

# Crea el realm community-day y el usuario demo en el Keycloak escritor actual.
bootstrap:
	scripts/bootstrap.sh

# Verifica AWS/Aurora/ARC y el estado esperado del writer y la reader antes de la demo.
demo-precheck:
	scripts/demo-precheck.sh

# Inserta una escritura de prueba para comprobar la región escritora actual.
write-probe:
	scripts/write-probe.sh

# OPERATION acepta switchover o failover. Failover exige ACCEPT_DATA_LOSS=yes.
# Inicia la ejecución de ARC hacia TARGET_REGION; devuelve su identificador.
arc-start:
	@test -n "$(OPERATION)" || { echo "Falta OPERATION. Uso: make arc-start OPERATION=switchover TARGET_REGION=us-east-1" >&2; exit 64; }
	@test -n "$(TARGET_REGION)" || { echo "Falta TARGET_REGION. Uso: make arc-start OPERATION=switchover TARGET_REGION=us-east-1" >&2; exit 64; }
	scripts/start-arc.sh "$(OPERATION)" "$(TARGET_REGION)"

# Consulta una ejecución de ARC hasta conocer si terminó correctamente o con error.
arc-poll:
	@test -n "$(OPERATION)" || { echo "Falta OPERATION. Uso: make arc-poll OPERATION=switchover EXECUTION_ID=<id>" >&2; exit 64; }
	@test -n "$(EXECUTION_ID)" || { echo "Falta EXECUTION_ID. Uso: make arc-poll OPERATION=switchover EXECUTION_ID=<id>" >&2; exit 64; }
	scripts/poll-arc.sh "$(OPERATION)" "$(EXECUTION_ID)"
