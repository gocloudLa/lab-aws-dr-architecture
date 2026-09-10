/*----------------------------------------------------------------------*/
/* Credenciales | Compartidas por las dos regiones                      */
/*----------------------------------------------------------------------*/

# Aurora Global Database replica las credenciales de la base: el clúster secundario
# hereda usuario y contraseña, así que ambos módulos regionales reciben el mismo valor.
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

# Sin wrapper en la Standard Platform: aws_rds_global_cluster no tiene equivalente y es
# el recurso que define la demo. Los clústeres regionales sí usan wrapper-rds-aurora.
resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier = "${var.metadata.key.company}-${var.metadata.key.env}-${var.metadata.key.project}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.aurora_engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
  force_destroy             = !var.deletion_protection
}

/*----------------------------------------------------------------------*/
/* Regiones | Blue (activa) y green (warm standby)                      */
/*----------------------------------------------------------------------*/

module "primary" {
  source = "../keycloak-region"

  providers = { aws = aws.primary }

  metadata   = var.metadata
  region_key = var.primary_region_key
  aws_region = var.primary_region

  vpc_name                    = var.primary_network.vpc_name
  app_subnet_name             = var.primary_network.app_subnet_name
  public_subnet_ids           = var.primary_network.public_subnet_ids
  database_subnet_ids         = var.primary_network.database_subnet_ids
  default_security_group_name = var.primary_network.default_security_group_name
  app_cidr_blocks             = var.primary_network.app_cidr_blocks
  peer_app_cidr_blocks        = var.secondary_network.app_cidr_blocks

  certificate_arn      = var.certificate_arn_primary
  public_domain_name   = var.public_domain_name
  app_hostname         = local.app_record_name
  regional_record_name = local.regional_records[var.primary_region_key]
  regional_hostname    = local.regional_hostnames[var.primary_region_key]

  global_cluster_identifier = aws_rds_global_cluster.this.id
  is_primary                = true
  global_writer_endpoint    = aws_rds_global_cluster.this.endpoint

  database_name           = var.database_name
  database_admin_username = var.database_admin_username
  database_password       = random_password.database.result
  aurora_engine_version   = var.aurora_engine_version
  serverless_min_acu      = var.serverless_min_acu
  serverless_max_acu      = var.serverless_max_acu
  deletion_protection     = var.deletion_protection

  container_image_tag               = var.container_image_tag
  ecs_desired_count                 = var.ecs_desired_count
  keycloak_bootstrap_admin_username = var.keycloak_bootstrap_admin_username
  keycloak_bootstrap_admin_password = random_password.keycloak_admin.result
}

# El clúster secundario sólo puede unirse al Global Database cuando el primario ya existe.
module "secondary" {
  source = "../keycloak-region"

  providers = { aws = aws.secondary }

  metadata   = var.metadata
  region_key = var.secondary_region_key
  aws_region = var.secondary_region

  vpc_name                    = var.secondary_network.vpc_name
  app_subnet_name             = var.secondary_network.app_subnet_name
  public_subnet_ids           = var.secondary_network.public_subnet_ids
  database_subnet_ids         = var.secondary_network.database_subnet_ids
  default_security_group_name = var.secondary_network.default_security_group_name
  app_cidr_blocks             = var.secondary_network.app_cidr_blocks
  peer_app_cidr_blocks        = var.primary_network.app_cidr_blocks

  certificate_arn      = var.certificate_arn_secondary
  public_domain_name   = var.public_domain_name
  app_hostname         = local.app_record_name
  regional_record_name = local.regional_records[var.secondary_region_key]
  regional_hostname    = local.regional_hostnames[var.secondary_region_key]

  global_cluster_identifier = aws_rds_global_cluster.this.id
  is_primary                = false
  global_writer_endpoint    = aws_rds_global_cluster.this.endpoint

  database_name           = var.database_name
  database_admin_username = var.database_admin_username
  database_password       = random_password.database.result
  aurora_engine_version   = var.aurora_engine_version
  serverless_min_acu      = var.serverless_min_acu
  serverless_max_acu      = var.serverless_max_acu
  deletion_protection     = var.deletion_protection

  container_image_tag               = var.container_image_tag
  ecs_desired_count                 = var.ecs_desired_count
  keycloak_bootstrap_admin_username = var.keycloak_bootstrap_admin_username
  keycloak_bootstrap_admin_password = random_password.keycloak_admin.result

  depends_on = [module.primary]
}
