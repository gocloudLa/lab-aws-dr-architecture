TF_EXAMPLES := terraform/examples/lab terraform/examples/complete
TF_DIR ?= terraform/examples/lab
TG_DIR ?= terragrunt

# Mientras se valida la migración conviven las dos orquestaciones. Los scripts leen los
# outputs según IAC_MODE (terragrunt por defecto; terraform para el stack anterior).
export IAC_MODE ?= terragrunt

.DEFAULT_GOAL := help

.PHONY: help init validate test-local local-up local-down build-push bootstrap \
	preflight demo-precheck write-probe fault-stop fault-restore arc-start arc-poll \
	tg-init tg-validate tg-fmt tg-graph tg-plan tg-apply tg-output tf-init tf-validate

help:
	@echo "Validación y entorno local:"
	@echo "  make init          # baja wrappers y providers de las dos orquestaciones"
	@echo "  make validate      # fmt, validate y contratos estáticos"
	@echo "  make test-local"
	@echo "  make local-up | make local-down"
	@echo "Stack Terragrunt (por capas, TG_DIR=$(TG_DIR)):"
	@echo "  make tg-graph      # DAG de dependencias entre capas"
	@echo "  make tg-plan       # plan de todas las capas"
	@echo "  make tg-apply      # apply de todo el stack en orden de dependencias"
	@echo "  make tg-output     # outputs agregados que consumen los scripts"
	@echo "Operación de la demo:"
	@echo "  make build-push TAG=demo-v1"
	@echo "  make bootstrap"
	@echo "  make preflight"
	@echo "  make demo-precheck"
	@echo "  make write-probe"
	@echo "  make fault-stop REGION=us-east-2"
	@echo "  make fault-restore REGION=us-east-2"
	@echo "  make arc-start OPERATION=switchover TARGET_REGION=us-east-1"
	@echo "  make arc-poll OPERATION=switchover EXECUTION_ID=<id>"

# ---------------------------------------------------------------------------
# Validación local (no requiere credenciales AWS)
# ---------------------------------------------------------------------------

init: tf-init tg-init

validate: test-local tf-validate tg-validate

test-local:
	@set -e; for script in scripts/*.sh scripts/tests/*.sh app/entrypoint.sh; do bash -n "$$script"; done
	scripts/tests/arc-contracts.sh
	scripts/tests/static-contracts.sh

# ---------------------------------------------------------------------------
# Terragrunt: orquestación por capas
# ---------------------------------------------------------------------------

# Cada capa resuelve sus propios providers; no configura backend remoto (state local).
tg-init:
	terragrunt run --all init --non-interactive --working-dir $(TG_DIR)

tg-fmt:
	terragrunt hcl fmt --working-dir $(TG_DIR)

tg-validate: tg-fmt
	terragrunt hcl validate --working-dir $(TG_DIR)

tg-graph:
	terragrunt dag graph --working-dir $(TG_DIR)

# Un plan desde cero sólo resuelve las capas project: las workload leen el ALB y el
# clúster ECS con data sources, que existen recién después del apply de las capas de abajo.
tg-plan:
	terragrunt run --all plan --non-interactive --working-dir $(TG_DIR)

# Un solo comando; Terragrunt respeta el DAG y paraleliza lo que es seguro.
tg-apply:
	terragrunt run --all apply --non-interactive --working-dir $(TG_DIR)

tg-output:
	scripts/show-outputs.sh

# ---------------------------------------------------------------------------
# Terraform: stack anterior, se conserva hasta validar la migración
# ---------------------------------------------------------------------------

tf-init:
	@set -e; for dir in $(TF_EXAMPLES); do terraform -chdir=$$dir init -backend=false; done

tf-validate:
	terraform -chdir=terraform fmt -check -recursive
	@set -e; for dir in $(TF_EXAMPLES); do terraform -chdir=$$dir validate; done

local-up:
	docker compose -f .docker/docker-compose.yml up --build -d

# Conserva los datos de PostgreSQL. Borrar el volumen con nombre es un paso aparte.
local-down:
	docker compose -f .docker/docker-compose.yml down

# ---------------------------------------------------------------------------
# Operación de la demo
# ---------------------------------------------------------------------------

# Construye una sola imagen y publica el mismo contenido en ambos ECR regionales.
build-push:
	@test -n "$(TAG)" || { echo "Falta TAG. Uso: make build-push TAG=demo-v1" >&2; exit 64; }
	scripts/build-push.sh "$(TAG)"

bootstrap:
	scripts/bootstrap.sh

preflight:
	scripts/preflight.sh

demo-precheck:
	scripts/demo-precheck.sh

write-probe:
	scripts/write-probe.sh

# Simula y revierte la caída de ECS; requiere una región válida de la demo.
fault-stop:
	@test -n "$(REGION)" || { echo "Falta REGION. Uso: make fault-stop REGION=us-east-2" >&2; exit 64; }
	scripts/app-fault.sh stop "$(REGION)"

fault-restore:
	@test -n "$(REGION)" || { echo "Falta REGION. Uso: make fault-restore REGION=us-east-2" >&2; exit 64; }
	scripts/app-fault.sh restore "$(REGION)"

# OPERATION acepta switchover o failover. Failover exige ACCEPT_DATA_LOSS=yes.
arc-start:
	@test -n "$(OPERATION)" || { echo "Falta OPERATION. Uso: make arc-start OPERATION=switchover TARGET_REGION=us-east-1" >&2; exit 64; }
	@test -n "$(TARGET_REGION)" || { echo "Falta TARGET_REGION. Uso: make arc-start OPERATION=switchover TARGET_REGION=us-east-1" >&2; exit 64; }
	scripts/start-arc.sh "$(OPERATION)" "$(TARGET_REGION)"

arc-poll:
	@test -n "$(OPERATION)" || { echo "Falta OPERATION. Uso: make arc-poll OPERATION=switchover EXECUTION_ID=<id>" >&2; exit 64; }
	@test -n "$(EXECUTION_ID)" || { echo "Falta EXECUTION_ID. Uso: make arc-poll OPERATION=switchover EXECUTION_ID=<id>" >&2; exit 64; }
	scripts/poll-arc.sh "$(OPERATION)" "$(EXECUTION_ID)"
