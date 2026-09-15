# Configuración raíz de Terragrunt. Emula la estructura de capas de la Standard Platform
# (<layer>/<project>/<environment>), pero con backend local: este lab no usa el bucket
# compartido de state ni los parámetros SSM /terraform/*.
#
# Por qué Terragrunt y no un único root module de Terraform: los wrappers de la Standard
# Platform resuelven ALB, target groups, clúster ECS y secretos con data sources internos
# cuyo for_each/count depende de valores que sólo existen después de crear la capa
# anterior. En un solo state, Terraform no puede expandir ese grafo y falla el plan con
# "Invalid for_each argument" / "Invalid count argument". Separando en capas, cada una
# planifica cuando los recursos de las capas inferiores ya existen y sus valores son
# concretos.

# El repo está pineado a Terraform (ver .terraform.lock.hcl y required_version); Terragrunt
# v1 usaría OpenTofu por defecto.
terraform_binary = "terraform"

# Backend local, un state por capa, fuera de .terragrunt-cache para que persista.
remote_state {
  backend = "local"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    path = "${get_parent_terragrunt_dir()}/.tfstate/${path_relative_to_include()}/terraform.tfstate"
  }
}

# Idéntico en todas las capas, así que se genera acá en vez de repetirlo.
generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    terraform {
      required_version = ">= 1.10"

      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 6.0"
        }
        random = {
          source  = "hashicorp/random"
          version = "~> 3.7"
        }
      }
    }
  EOF
}
