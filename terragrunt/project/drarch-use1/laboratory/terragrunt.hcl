include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "global" {
  config_path = "../../drarch-global/laboratory"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    global_cluster_identifier    = "mock-global"
    aurora_engine_version        = "16.14"
    database_name                = "keycloak"
    database_admin_username      = "keycloak_admin"
    database_password            = "mock-password"
    aurora_kms_key_arn_secondary = "arn:aws:kms:us-east-1:000000000000:key/mock"
    secret_suffix                = "mock01"
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

  # Clave KMS de esta región (Virginia), creada en la capa global.
  aurora_kms_key_arn = dependency.global.outputs.aurora_kms_key_arn_secondary

  # Sufijo del nombre del secreto de Aurora, generado en la capa global.
  secret_suffix = dependency.global.outputs.secret_suffix

  # Virginia arranca como réplica de sólo lectura del Global Database.
  is_primary_cluster = false

  # Región del clúster primario. Se declara igual que aws_region en metadata.tf de cada capa,
  # que es la convención del repo para las regiones fijas de este lab.
  source_region = "us-east-2"

  aurora_instance_class = "db.r6g.large"

  deletion_protection = false
}
