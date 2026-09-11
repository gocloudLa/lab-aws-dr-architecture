data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Endpoint del clúster Aurora *local* a esta región, no el Global Writer Endpoint. Cada
# Keycloak lee y escribe siempre contra su propio clúster: el primario porque es el writer,
# y el secundario porque ARC lo promueve antes de escalar el ECS de esa región (ver arc.tf).
# Así ninguna carga necesita cruzar de región por PostgreSQL y no hace falta peering.
data "aws_rds_cluster" "this" {
  cluster_identifier = local.aurora_cluster_name

  depends_on = [module.aurora]
}

locals {
  # Los wrappers de la capa de workload derivan este nombre de metadata.key; se recalcula
  # acá porque ninguno de ellos expone outputs con los nombres que generan.
  common_name = join("-", [
    var.metadata.key.company,
    var.metadata.key.env,
    var.metadata.key.project
  ])

  # metadata regional: cada instancia del módulo declara su propia región.
  metadata = merge(var.metadata, {
    aws_region = var.aws_region
    key        = merge(var.metadata.key, { region = var.region_key })
  })

  ecs_cluster_key        = "00"
  ecs_service_key        = "keycloak"
  ecs_container_key      = "app"
  ecr_repository_key     = "keycloak"
  alb_listener_key       = "443"
  ecs_cluster_name       = "${local.common_name}-${local.ecs_cluster_key}"
  ecs_service_name       = "${local.common_name}-${local.ecs_service_key}"
  aurora_cluster_name    = "${local.common_name}-${var.region_key}"
  ecr_repository_name    = "${local.common_name}-${local.ecr_repository_key}"
  ecr_repository_url     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${local.ecr_repository_name}"
  keycloak_image         = "${local.ecr_repository_url}:${var.container_image_tag}"
  target_group_name      = "${local.common_name}-kc-${var.region_key}"
  aurora_engine_major    = split(".", var.aurora_engine_version)[0]
  aurora_parameter_group = "aurora-postgresql${local.aurora_engine_major}"

  # wrapper-alb no publica el nombre del ALB, y wrapper-ecs-service lo necesita como string
  # para resolverlo por data source. En vez de recomponerlo como literal se deriva del ARN
  # del listener 443: así es un atributo real de un recurso creado, la dependencia queda
  # implícita y Terraform garantiza que el listener exista antes de que lo busquen.
  # Formato del ARN: arn:...:listener/app/<nombre-alb>/<id-alb>/<id-listener>
  alb_name = split("/", module.alb.alb[var.region_key].listeners[local.alb_listener_key].arn)[2]

  # Aurora sólo acepta PostgreSQL desde las subredes de aplicación de su propia región:
  # cada Keycloak conecta siempre al clúster local (ver data.aws_rds_cluster.this en
  # locals.tf), nunca cruza a la otra región, así que no hace falta abrir el CIDR remoto
  # ni depender de peering entre las VPC.
  database_ingress_cidrs = join(",", var.app_cidr_blocks)
}
