include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "project" {
  config_path = "../../../project/drarch-use1/laboratory"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    aws_region              = "us-east-1"
    region_key              = "use1"
    common_name_prefix      = "dmc-lab"
    app_subnet_name         = "dmc-lab-private*"
    ecs_cluster_name        = "dmc-lab-drarch-00"
    ecs_cluster_arn         = "arn:aws:ecs:us-east-1:000000000000:cluster/mock"
    alb_name                = "dmc-lab-drarch-use1"
    ecr_repository_url      = "000000000000.dkr.ecr.us-east-1.amazonaws.com/mock"
    aurora_cluster_endpoint = "mock.cluster.rds.amazonaws.com"
    app_hostname            = "app.lab.democorp.cloud"
    regional_hostname       = "app-use1.lab.democorp.cloud"
  }
}

dependency "global" {
  config_path = "../../../project/drarch-global/laboratory"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    database_name                     = "keycloak"
    database_admin_username           = "keycloak_admin"
    database_password                 = "mock-password"
    keycloak_bootstrap_admin_username = "admin"
    keycloak_bootstrap_admin_password = "mock-password"
  }
}

inputs = {
  aws_region         = dependency.project.outputs.aws_region
  region_key         = dependency.project.outputs.region_key
  vpc_name           = dependency.project.outputs.common_name_prefix
  app_subnet_name    = dependency.project.outputs.app_subnet_name
  ecs_cluster_name   = dependency.project.outputs.ecs_cluster_name
  alb_name           = dependency.project.outputs.alb_name
  ecr_repository_url = dependency.project.outputs.ecr_repository_url
  app_hostname       = dependency.project.outputs.app_hostname
  regional_hostname  = dependency.project.outputs.regional_hostname
  db_host            = dependency.project.outputs.aurora_cluster_endpoint

  database_name                     = dependency.global.outputs.database_name
  database_admin_username           = dependency.global.outputs.database_admin_username
  database_password                 = dependency.global.outputs.database_password
  keycloak_bootstrap_admin_username = dependency.global.outputs.keycloak_bootstrap_admin_username
  keycloak_bootstrap_admin_password = dependency.global.outputs.keycloak_bootstrap_admin_password

  # Misma imagen que Ohio (digest idéntico): la task definition debe apuntar a la imagen real
  # para que ARC pueda escalar el servicio durante el switchover sin recrear nada.
  container_image_tag = "demo-v1"

  # Warm standby: Virginia corre 1 tarea permanentemente, igual que Ohio. La task definition
  # usa targetServerType=any para no rechazar el Aurora reader durante la conexión; ARC debe
  # promoverlo antes de dirigir tráfico porque la propiedad no habilita escrituras.
  ecs_desired_count = 1
}
