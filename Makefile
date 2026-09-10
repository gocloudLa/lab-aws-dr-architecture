TF_EXAMPLES := terraform/examples/lab terraform/examples/complete
TF_DIR ?= terraform/examples/lab

.DEFAULT_GOAL := help

.PHONY: help init validate test-local local-up local-down build-push bootstrap \
	preflight demo-precheck write-probe fault-stop fault-restore arc-start arc-poll

help:
	@echo "Validación y entorno local:"
	@echo "  make init"
	@echo "  make validate"
	@echo "  make test-local"
	@echo "  make local-up | make local-down"
	@echo "Operación de la demo (TF_DIR=$(TF_DIR)):"
	@echo "  make build-push TAG=demo-v1"
	@echo "  make bootstrap"
	@echo "  make preflight"
	@echo "  make demo-precheck"
	@echo "  make write-probe"
	@echo "  make fault-stop REGION=us-east-2"
	@echo "  make fault-restore REGION=us-east-2"
	@echo "  make arc-start OPERATION=switchover TARGET_REGION=us-east-1"
	@echo "  make arc-poll OPERATION=switchover EXECUTION_ID=<id>"

# Baja wrappers y providers. No configura backend ni necesita credenciales AWS.
init:
	@set -e; for dir in $(TF_EXAMPLES); do terraform -chdir=$$dir init -backend=false; done

# Sólo validación estática: no ejecuta plan ni apply.
validate: test-local
	terraform -chdir=terraform fmt -check -recursive
	@set -e; for dir in $(TF_EXAMPLES); do terraform -chdir=$$dir validate; done

test-local:
	@set -e; for script in scripts/*.sh scripts/tests/*.sh app/entrypoint.sh; do bash -n "$$script"; done
	scripts/tests/arc-contracts.sh
	scripts/tests/static-contracts.sh

local-up:
	docker compose -f .docker/docker-compose.yml up --build -d

# Conserva los datos de PostgreSQL. Borrar el volumen con nombre es un paso aparte.
local-down:
	docker compose -f .docker/docker-compose.yml down

# Construye una sola imagen y publica el mismo contenido en ambos ECR regionales.
build-push:
	@test -n "$(TAG)" || { echo "Falta TAG. Uso: make build-push TAG=demo-v1" >&2; exit 64; }
	TF_DIR="$(TF_DIR)" scripts/build-push.sh "$(TAG)"

bootstrap:
	scripts/bootstrap.sh

preflight:
	TF_DIR="$(TF_DIR)" scripts/preflight.sh

demo-precheck:
	TF_DIR="$(TF_DIR)" scripts/demo-precheck.sh

write-probe:
	scripts/write-probe.sh

# Simula y revierte la caída de ECS; requiere una región válida de la demo.
fault-stop:
	@test -n "$(REGION)" || { echo "Falta REGION. Uso: make fault-stop REGION=us-east-2" >&2; exit 64; }
	TF_DIR="$(TF_DIR)" scripts/app-fault.sh stop "$(REGION)"

fault-restore:
	@test -n "$(REGION)" || { echo "Falta REGION. Uso: make fault-restore REGION=us-east-2" >&2; exit 64; }
	TF_DIR="$(TF_DIR)" scripts/app-fault.sh restore "$(REGION)"

# OPERATION acepta switchover o failover. Failover exige ACCEPT_DATA_LOSS=yes.
arc-start:
	@test -n "$(OPERATION)" || { echo "Falta OPERATION. Uso: make arc-start OPERATION=switchover TARGET_REGION=us-east-1" >&2; exit 64; }
	@test -n "$(TARGET_REGION)" || { echo "Falta TARGET_REGION. Uso: make arc-start OPERATION=switchover TARGET_REGION=us-east-1" >&2; exit 64; }
	TF_DIR="$(TF_DIR)" scripts/start-arc.sh "$(OPERATION)" "$(TARGET_REGION)"

arc-poll:
	@test -n "$(OPERATION)" || { echo "Falta OPERATION. Uso: make arc-poll OPERATION=switchover EXECUTION_ID=<id>" >&2; exit 64; }
	@test -n "$(EXECUTION_ID)" || { echo "Falta EXECUTION_ID. Uso: make arc-poll OPERATION=switchover EXECUTION_ID=<id>" >&2; exit 64; }
	TF_DIR="$(TF_DIR)" scripts/poll-arc.sh "$(OPERATION)" "$(EXECUTION_ID)"
