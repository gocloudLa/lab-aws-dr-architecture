include "root" {
  path = find_in_parent_folders("root.hcl")
}

# La capa project ya creó ECR, Aurora, ALB y el clúster ECS. Sus outputs llegan acá como
# valores concretos, así el for_each de los target groups y de la task definition del
# wrapper de ECS Service se puede expandir en tiempo de plan.
dependency "project" {
  config_path = "../../../project/drarch-use2/laboratory"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    aws_region              = "us-east-2"
    region_key              = "use2"
    common_name_prefix      = "dmc-lab"
    app_subnet_name         = "dmc-lab-private*"
    ecs_cluster_name        = "dmc-lab-drarch-00"
    ecs_cluster_arn         = "arn:aws:ecs:us-east-2:000000000000:cluster/mock"
    alb_name                = "dmc-lab-drarch-use2"
    ecr_repository_url      = "000000000000.dkr.ecr.us-east-2.amazonaws.com/mock"
    aurora_cluster_endpoint = "mock.cluster.rds.amazonaws.com"
    app_hostname            = "app.lab.democorp.cloud"
    regional_hostname       = "app-use2.lab.democorp.cloud"
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

  # DB_HOST es el endpoint del clúster Aurora de esta misma región, no el Global Writer
  # Endpoint: ninguna carga cruza de región, así que no hace falta peering entre VPC.
  db_host = dependency.project.outputs.aurora_cluster_endpoint

  database_name                     = dependency.global.outputs.database_name
  database_admin_username           = dependency.global.outputs.database_admin_username
  database_password                 = dependency.global.outputs.database_password
  keycloak_bootstrap_admin_username = dependency.global.outputs.keycloak_bootstrap_admin_username
  keycloak_bootstrap_admin_password = dependency.global.outputs.keycloak_bootstrap_admin_password

  # Imagen publicada en ambos ECR con digest idéntico (make build-push TAG=demo-v1).
  container_image_tag = "demo-v1"

  # Warm standby: Ohio y Virginia corren 1 tarea (misma config). Ohio arranca como writer, así
  # que su tarea está sana; Virginia corre pero falla en bucle hasta que ARC promueve su Aurora.
  ecs_desired_count = 1
}
