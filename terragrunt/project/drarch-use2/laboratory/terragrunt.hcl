include "root" {
  path = find_in_parent_folders("root.hcl")
}

# El identificador del Global Database y las credenciales llegan como valores concretos
# leídos del state de la capa global. Es lo que evita que el for_each interno del wrapper
# de Aurora dependa de un valor unknown.
dependency "global" {
  config_path = "../../drarch-global/laboratory"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    global_cluster_identifier = "mock-global"
    aurora_engine_version     = "16.14"
    database_name             = "keycloak"
    database_admin_username   = "keycloak_admin"
    database_password         = "mock-password"
  }
}

inputs = {
  global_cluster_identifier = dependency.global.outputs.global_cluster_identifier
  aurora_engine_version     = dependency.global.outputs.aurora_engine_version
  database_name             = dependency.global.outputs.database_name
  database_admin_username   = dependency.global.outputs.database_admin_username
  database_password         = dependency.global.outputs.database_password

  # Ohio arranca como writer del Global Database.
  is_primary_cluster = true

  # Aurora Global Database no admite clases burstable (db.t3/db.t4g): la memory-optimized
  # más chica disponible en us-east-1 y us-east-2 para 16.14 es db.r6g.large.
  aurora_instance_class = "db.r6g.large"

  deletion_protection = false
}
