locals {
  metadata = {
    aws_region      = "us-east-1"
    environment     = "Laboratory"
    project         = "aws-dr-architecture"
    public_domain   = "democorp.cloud"
    private_domain  = "democorp.private"
    internal_domain = "democorp.internal"

    key = {
      company = "dmc"
      env     = "lab"
      project = "drarch"
      region  = "use1"
      layer   = "project"
    }

    common_tags = {
      company     = "dmc"
      environment = "Laboratory"
      project     = "aws-dr-architecture"
      provisioner = "terraform"
      created-by  = "GoCloud.la"
      demo        = "dr-architecture"
    }
  }

  common_name_prefix = join("-", [
    local.metadata.key.company,
    local.metadata.key.env
  ])

  common_name = join("-", [
    local.common_name_prefix,
    local.metadata.key.project
  ])

  # Claves de recurso dentro de cada wrapper. La región es la clave de Aurora y del ALB,
  # así los nombres quedan dmc-lab-drarch-use2 y no colisionan entre regiones.
  region_key         = local.metadata.key.region
  ecr_repository_key = "keycloak"
  ecs_cluster_key    = "00"

  ecs_cluster_name    = "${local.common_name}-${local.ecs_cluster_key}"
  aurora_cluster_name = "${local.common_name}-${local.region_key}"
  ecr_repository_name = "${local.common_name}-${local.ecr_repository_key}"
  alb_name            = "${local.common_name}-${local.region_key}"
}
