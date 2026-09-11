provider "aws" {
  region = local.metadata.aws_region
}

# Las claves KMS son regionales. La capa global es la única cross-region del stack, así que
# aquí se crean las dos claves (Ohio y Virginia) y sus ARN viajan como outputs concretos a
# las capas regionales: nacen en la capa más baja para no reintroducir un valor unknown en
# el plan de Aurora (que es justo lo que Terragrunt vino a evitar).
provider "aws" {
  alias  = "secondary"
  region = local.secondary_region
}
