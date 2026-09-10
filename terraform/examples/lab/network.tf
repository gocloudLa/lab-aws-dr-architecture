# La red ya existe, así que resolverla por tag es correcto: no hay nada que crear y no hay
# orden que garantizar. El stack recibe IDs concretos y no vuelve a buscar estas subredes.

data "aws_vpc" "primary" {
  provider = aws.primary

  filter {
    name   = "tag:Name"
    values = [var.primary_network.vpc_name]
  }
}

data "aws_subnets" "primary_public" {
  provider = aws.primary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  tags = {
    Name = var.primary_network.public_subnet_name
  }
}

data "aws_subnets" "primary_database" {
  provider = aws.primary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  tags = {
    Name = var.primary_network.database_subnet_name
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  filter {
    name   = "tag:Name"
    values = [var.secondary_network.vpc_name]
  }
}

data "aws_subnets" "secondary_public" {
  provider = aws.secondary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  tags = {
    Name = var.secondary_network.public_subnet_name
  }
}

data "aws_subnets" "secondary_database" {
  provider = aws.secondary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  tags = {
    Name = var.secondary_network.database_subnet_name
  }
}

locals {
  network = {
    primary = {
      vpc_name                    = var.primary_network.vpc_name
      app_subnet_name             = var.primary_network.app_subnet_name
      default_security_group_name = var.primary_network.default_security_group_name
      public_subnet_ids           = data.aws_subnets.primary_public.ids
      database_subnet_ids         = data.aws_subnets.primary_database.ids
      app_cidr_blocks             = var.primary_network.app_cidr_blocks
    }
    secondary = {
      vpc_name                    = var.secondary_network.vpc_name
      app_subnet_name             = var.secondary_network.app_subnet_name
      default_security_group_name = var.secondary_network.default_security_group_name
      public_subnet_ids           = data.aws_subnets.secondary_public.ids
      database_subnet_ids         = data.aws_subnets.secondary_database.ids
      app_cidr_blocks             = var.secondary_network.app_cidr_blocks
    }
  }
}

# Fallar temprano y con un mensaje claro es mejor que un error opaco de ALB o de Aurora.
check "subredes_encontradas" {
  assert {
    condition     = length(data.aws_subnets.primary_public.ids) >= 2 && length(data.aws_subnets.secondary_public.ids) >= 2
    error_message = "Cada región necesita al menos dos subredes públicas que coincidan con public_subnet_name."
  }

  assert {
    condition     = length(data.aws_subnets.primary_database.ids) >= 2 && length(data.aws_subnets.secondary_database.ids) >= 2
    error_message = "Cada región necesita al menos dos subredes de base de datos que coincidan con database_subnet_name."
  }
}
