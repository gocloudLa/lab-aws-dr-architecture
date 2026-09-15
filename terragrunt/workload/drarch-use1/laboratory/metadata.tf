locals {
  metadata = {
    aws_region      = var.aws_region
    environment     = "Laboratory"
    project         = "aws-dr-architecture"
    public_domain   = "democorp.cloud"
    private_domain  = "democorp.private"
    internal_domain = "democorp.internal"

    key = {
      company = "dmc"
      env     = "lab"
      project = "drarch"
      region  = var.region_key
      layer   = "workload"
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

  ecs_service_key   = "keycloak"
  ecs_container_key = "app"

  ecs_service_name  = "${local.common_name}-${local.ecs_service_key}"
  target_group_name = "${local.common_name}-kc-${var.region_key}"
  keycloak_image    = "${var.ecr_repository_url}:${var.container_image_tag}"
}
