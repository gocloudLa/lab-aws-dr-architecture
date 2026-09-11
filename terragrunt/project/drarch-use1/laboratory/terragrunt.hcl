include "root" {
  path = find_in_parent_folders("root.hcl")
}

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

# Ordenamiento sin pasar valores: un clúster secundario sólo puede unirse al Global
# Database cuando el primario ya existe.
dependencies {
  paths = ["../../drarch-use2/laboratory"]
}

inputs = {
  global_cluster_identifier = dependency.global.outputs.global_cluster_identifier
  aurora_engine_version     = dependency.global.outputs.aurora_engine_version
  database_name             = dependency.global.outputs.database_name
  database_admin_username   = dependency.global.outputs.database_admin_username
  database_password         = dependency.global.outputs.database_password

  # Virginia arranca como réplica de sólo lectura del Global Database.
  is_primary_cluster = false

  aurora_instance_class = "db.r6g.large"

  deletion_protection = false
}
