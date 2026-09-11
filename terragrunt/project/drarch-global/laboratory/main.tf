/*----------------------------------------------------------------------*/
/* Credenciales | Compartidas por las dos regiones                      */
/*----------------------------------------------------------------------*/

# Aurora Global Database replica las credenciales: el clúster secundario hereda usuario y
# contraseña, así que se generan una sola vez acá y las capas regionales las reciben como
# input de Terragrunt (valor concreto leído del state de esta capa, no un valor unknown).
resource "random_password" "database" {
  length  = 32
  special = false
}

resource "random_password" "keycloak_admin" {
  length  = 32
  special = true
}

/*----------------------------------------------------------------------*/
/* Aurora Global Database                                               */
/*----------------------------------------------------------------------*/

# Capa propia porque su identificador alimenta el for_each/count interno del wrapper de
# Aurora en las capas regionales. Creado acá, ese valor ya es concreto cuando esas capas
# hacen plan.
resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${local.common_name}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.aurora_engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
  force_destroy             = !var.deletion_protection
}
