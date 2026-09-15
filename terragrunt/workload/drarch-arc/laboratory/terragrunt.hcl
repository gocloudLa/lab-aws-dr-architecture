include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Última capa: el plan de ARC referencia ARNs de Aurora, del clúster ECS y del servicio ECS
# de las dos regiones, y los registros FAILOVER necesitan los ALB ya creados. Todos esos
# valores llegan concretos desde las capas inferiores.

dependency "global" {
  config_path = "../../../project/drarch-global/laboratory"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    global_cluster_identifier = "mock-global"
    global_cluster_arn        = "arn:aws:rds::000000000000:global-cluster:mock"
  }
}

dependency "project_use2" {
  config_path = "../../../project/drarch-use2/laboratory"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    aws_region         = "us-east-2"
    region_key         = "use2"
    aurora_cluster_arn = "arn:aws:rds:us-east-2:000000000000:cluster:mock"
    alb_dns_name       = "mock-use2.us-east-2.elb.amazonaws.com"
    alb_zone_id        = "Z3AADJGX6KTTL2"
    app_hostname       = "app.lab.democorp.cloud"
    zone_public        = "lab.democorp.cloud"
  }
}

dependency "project_use1" {
  config_path = "../../../project/drarch-use1/laboratory"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    aws_region         = "us-east-1"
    region_key         = "use1"
    aurora_cluster_arn = "arn:aws:rds:us-east-1:000000000000:cluster:mock"
    alb_dns_name       = "mock-use1.us-east-1.elb.amazonaws.com"
    alb_zone_id        = "Z35SXDOTRQ7X7K"
  }
}

dependency "workload_use2" {
  config_path = "../../drarch-use2/laboratory"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    ecs_cluster_arn = "arn:aws:ecs:us-east-2:000000000000:cluster/mock"
    ecs_service_arn = "arn:aws:ecs:us-east-2:000000000000:service/mock/mock"
  }
}

dependency "workload_use1" {
  config_path = "../../drarch-use1/laboratory"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    ecs_cluster_arn = "arn:aws:ecs:us-east-1:000000000000:cluster/mock"
    ecs_service_arn = "arn:aws:ecs:us-east-1:000000000000:service/mock/mock"
  }
}

inputs = {
  primary_region   = dependency.project_use2.outputs.aws_region
  secondary_region = dependency.project_use1.outputs.aws_region

  global_cluster_identifier = dependency.global.outputs.global_cluster_identifier
  global_cluster_arn        = dependency.global.outputs.global_cluster_arn

  primary_aurora_cluster_arn   = dependency.project_use2.outputs.aurora_cluster_arn
  secondary_aurora_cluster_arn = dependency.project_use1.outputs.aurora_cluster_arn

  primary_alb_dns_name   = dependency.project_use2.outputs.alb_dns_name
  primary_alb_zone_id    = dependency.project_use2.outputs.alb_zone_id
  secondary_alb_dns_name = dependency.project_use1.outputs.alb_dns_name
  secondary_alb_zone_id  = dependency.project_use1.outputs.alb_zone_id

  primary_ecs_cluster_arn   = dependency.workload_use2.outputs.ecs_cluster_arn
  primary_ecs_service_arn   = dependency.workload_use2.outputs.ecs_service_arn
  secondary_ecs_cluster_arn = dependency.workload_use1.outputs.ecs_cluster_arn
  secondary_ecs_service_arn = dependency.workload_use1.outputs.ecs_service_arn

  app_hostname = dependency.project_use2.outputs.app_hostname
  zone_public  = dependency.project_use2.outputs.zone_public

  # switchoverOnly para una operación planificada; failover acepta posible pérdida.
  arc_aurora_behavior                 = "switchoverOnly"
  arc_recovery_time_objective_minutes = 45
}
