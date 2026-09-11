# Variante completa: crea también la red, para levantar la demo desde cero en una cuenta
# vacía. Si ya tenés VPC, NAT y subredes, usar examples/lab.

locals {
  # Todo lo que el stack necesita sale de atributos de los recursos creados, no de
  # literales: vpc_name es el tag Name real de la VPC y los IDs de subred son los de las
  # subredes creadas. Eso convierte la dependencia con la red en implícita.
  network = {
    primary = {
      vpc_name                    = module.vpc_primary.vpcs[local.vpc_key].vpc_name
      app_subnet_name             = "${module.vpc_primary.vpcs[local.vpc_key].vpc_name}-private*"
      default_security_group_name = "${module.vpc_primary.vpcs[local.vpc_key].vpc_name}-default"
      public_subnet_ids           = [for az in ["a", "b"] : module.vpc_primary.subnets["${local.vpc_key}-public-${az}"].id]
      database_subnet_ids         = [for az in ["a", "b"] : module.vpc_primary.subnets["${local.vpc_key}-database-${az}"].id]
      app_cidr_blocks             = local.app_cidr_blocks.primary
    }
    secondary = {
      vpc_name                    = module.vpc_secondary.vpcs[local.vpc_key].vpc_name
      app_subnet_name             = "${module.vpc_secondary.vpcs[local.vpc_key].vpc_name}-private*"
      default_security_group_name = "${module.vpc_secondary.vpcs[local.vpc_key].vpc_name}-default"
      public_subnet_ids           = [for az in ["a", "b"] : module.vpc_secondary.subnets["${local.vpc_key}-public-${az}"].id]
      database_subnet_ids         = [for az in ["a", "b"] : module.vpc_secondary.subnets["${local.vpc_key}-database-${az}"].id]
      app_cidr_blocks             = local.app_cidr_blocks.secondary
    }
  }
}

module "dr_architecture" {
  source = "../../modules/dr-architecture"

  providers = {
    aws.primary   = aws.primary
    aws.secondary = aws.secondary
  }

  metadata = local.metadata

  primary_region       = var.primary_region
  secondary_region     = var.secondary_region
  primary_region_key   = var.primary_region_key
  secondary_region_key = var.secondary_region_key

  primary_network   = local.network.primary
  secondary_network = local.network.secondary

  public_zone_id            = var.public_zone_id
  public_domain_name        = var.public_domain_name
  certificate_arn_primary   = var.certificate_arn_primary
  certificate_arn_secondary = var.certificate_arn_secondary

  aurora_engine_version = var.aurora_engine_version
  aurora_instance_class = var.aurora_instance_class
  container_image_tag   = var.container_image_tag
  ecs_desired_count     = var.ecs_desired_count
  arc_aurora_behavior   = var.arc_aurora_behavior
  deletion_protection   = var.deletion_protection

  # Las subredes públicas y de base de datos llegan por ID, así que su dependencia ya es
  # implícita. Este depends_on cubre sólo las subredes privadas: wrapper-ecs-service es el
  # único wrapper que no acepta IDs y las resuelve por tag, sin ningún atributo al que
  # referirse. Es el caso que la documentación de Terraform reserva para depends_on.
  depends_on = [module.vpc_primary, module.vpc_secondary]
}
