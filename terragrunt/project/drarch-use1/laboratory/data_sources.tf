data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# La red ya existe y se resuelve por tag Name, igual que en los blueprints de la Standard
# Platform. common_name_prefix (dmc-lab) coincide con el tag real de la VPC, así que los
# wrappers también aciertan con sus defaults.
data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = [local.common_name_prefix]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    Name = "${local.common_name_prefix}-public*"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    Name = "${local.common_name_prefix}-private*"
  }
}

data "aws_subnets" "database" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    Name = "${local.common_name_prefix}-db*"
  }
}

# Los CIDR de las subredes de aplicación alimentan el ingress PostgreSQL de Aurora. Se leen
# de la red real en vez de hardcodearlos: si la red cambia, el ingress sigue siendo correcto.
data "aws_subnet" "private" {
  for_each = toset(data.aws_subnets.private.ids)
  id       = each.value
}

# Certificado regional que cubre app.<zona> y app-<region>.<zona>.
data "aws_acm_certificate" "this" {
  domain      = local.zone_public
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}

locals {
  app_cidr_blocks = sort([for subnet in data.aws_subnet.private : subnet.cidr_block])
}

# Fallar temprano y con mensaje claro es mejor que un error opaco de ALB o de Aurora.
check "red_encontrada" {
  assert {
    condition     = length(data.aws_subnets.public.ids) >= 2
    error_message = "Se necesitan al menos dos subredes públicas con tag ${local.common_name_prefix}-public* para el ALB."
  }

  assert {
    condition     = length(data.aws_subnets.database.ids) >= 2
    error_message = "Se necesitan al menos dos subredes de base de datos con tag ${local.common_name_prefix}-db* para Aurora."
  }

  assert {
    condition     = length(data.aws_subnets.private.ids) >= 1
    error_message = "Se necesita al menos una subred privada con tag ${local.common_name_prefix}-private* para las tareas ECS."
  }
}
