# Variante de laboratorio: reutiliza VPC, NAT y subredes ya existentes en cada región.
# Para levantar la demo desde cero, incluida la red, usar examples/complete.

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

  container_image_tag = var.container_image_tag
  ecs_desired_count   = var.ecs_desired_count
  arc_aurora_behavior = var.arc_aurora_behavior
  deletion_protection = var.deletion_protection
}
