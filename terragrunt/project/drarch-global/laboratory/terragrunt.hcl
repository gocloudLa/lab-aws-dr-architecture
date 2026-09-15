include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Primera capa del stack: no depende de nada.
inputs = {
  aurora_engine_version = "16.14"
  database_name         = "keycloak"
  deletion_protection   = false
}
