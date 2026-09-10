/*----------------------------------------------------------------------*/
/* VPC | Una por región, con el naming que espera la capa de workload    */
/*----------------------------------------------------------------------*/

# Las subredes de aplicación son privadas y salen por NAT: las tareas Keycloak no
# reciben IP pública. Un NAT por región es una concesión de laboratorio: no da alta
# disponibilidad de NAT dentro de la región.

locals {
  vpc_parameters = {
    for role, cidr in { primary = var.primary_vpc_cidr, secondary = var.secondary_vpc_cidr } :
    role => {
      (local.vpc_key) = {
        vpc_cidr = cidr

        internet_gateway = {
          igw = {}
        }

        nat_gateway = {
          natgw = {
            subnet = "public-a"
            kind   = "aws"
          }
        }

        route_table = {
          public   = { default_route = { gateway = "igw" } }
          private  = { default_route = { nat_gateway = "natgw" } }
          database = {}
        }

        subnets = {
          public = {
            a = { cidr_block = cidrsubnet(cidr, 4, 0), az = "a", route_table = "public" }
            b = { cidr_block = cidrsubnet(cidr, 4, 1), az = "b", route_table = "public" }
          }
          private = {
            a = { cidr_block = cidrsubnet(cidr, 4, 4), az = "a", route_table = "private" }
            b = { cidr_block = cidrsubnet(cidr, 4, 5), az = "b", route_table = "private" }
          }
          database = {
            a = { cidr_block = cidrsubnet(cidr, 4, 8), az = "a", route_table = "database" }
            b = { cidr_block = cidrsubnet(cidr, 4, 9), az = "b", route_table = "database" }
          }
        }
      }
    }
  }
}

module "vpc_primary" {
  source  = "gocloudLa/wrapper-vpc/aws"
  version = "2.1.0"

  providers = { aws = aws.primary }

  metadata       = local.metadata
  vpc_parameters = local.vpc_parameters.primary
}

module "vpc_secondary" {
  source  = "gocloudLa/wrapper-vpc/aws"
  version = "2.1.0"

  providers = { aws = aws.secondary }

  metadata       = local.metadata
  vpc_parameters = local.vpc_parameters.secondary
}

/*----------------------------------------------------------------------*/
/* Peering | Interregional, en dos mitades                              */
/*----------------------------------------------------------------------*/

# El wrapper no modela un peering cross-region en una sola invocación: la mitad
# solicitante crea la conexión y sus rutas en la región primaria, y la mitad aceptante
# la acepta y crea sus rutas en la secundaria, cada una con su propio provider.

module "peering_primary" {
  source  = "gocloudLa/wrapper-peering/aws"
  version = "0.1.0"

  providers = { aws = aws.primary }

  metadata = local.metadata

  vpc_parameter = {
    vpcs         = module.vpc_primary.vpcs
    route_tables = module.vpc_primary.route_tables
  }

  peering_parameters = {
    dr = {
      create_peer = true
      # auto_accept no aplica entre regiones: la acepta la otra mitad del peering.
      auto_accept     = false
      peer_region     = var.secondary_region
      vpc             = local.vpc_key
      vpc_accepter_id = module.vpc_secondary.vpcs[local.vpc_key].vpc_id

      requester = {
        allow_remote_vpc_dns_resolution = true
      }

      vpc_routes = {
        (local.vpc_key) = {
          private  = { destination_cidr_block = [var.secondary_vpc_cidr] }
          database = { destination_cidr_block = [var.secondary_vpc_cidr] }
        }
      }
    }
  }
}

module "peering_secondary" {
  source  = "gocloudLa/wrapper-peering/aws"
  version = "0.1.0"

  providers = { aws = aws.secondary }

  metadata = local.metadata

  vpc_parameter = {
    vpcs         = module.vpc_secondary.vpcs
    route_tables = module.vpc_secondary.route_tables
  }

  peering_parameters = {
    dr = {
      create_peer  = false
      auto_accept  = true
      peering_id   = module.peering_primary.vpc_peering_connections["dr"].id
      vpc          = local.vpc_key
      vpc_accepter = local.vpc_key

      accepter = {
        allow_remote_vpc_dns_resolution = true
      }

      vpc_routes = {
        (local.vpc_key) = {
          private  = { destination_cidr_block = [var.primary_vpc_cidr] }
          database = { destination_cidr_block = [var.primary_vpc_cidr] }
        }
      }
    }
  }
}
