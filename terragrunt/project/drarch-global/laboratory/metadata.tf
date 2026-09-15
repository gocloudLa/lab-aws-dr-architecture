locals {
  metadata = {
    aws_region      = "us-east-2"
    environment     = "Laboratory"
    project         = "aws-dr-architecture"
    public_domain   = "democorp.cloud"
    private_domain  = "democorp.private"
    internal_domain = "democorp.internal"

    key = {
      company = "dmc"
      env     = "lab"
      project = "drarch"
      region  = "use2"
      layer   = "project"
    }

    common_tags = {
      company     = "dmc"
      environment = "Laboratory"
      project     = "aws-dr-architecture"
      provisioner = "terraform"
      created-by  = "GoCloud.la"
      demo        = "dr-architecture"
    }
  }

  # dmc-lab: coincide con el tag Name de la VPC preexistente, así los wrappers resuelven
  # la red con sus defaults sin necesidad de pasarles vpc_name.
  common_name_prefix = join("-", [
    local.metadata.key.company,
    local.metadata.key.env
  ])

  # dmc-lab-drarch
  common_name = join("-", [
    local.common_name_prefix,
    local.metadata.key.project
  ])

  # Región del clúster secundario del Global Database. La capa global crea una clave KMS en
  # cada región, así que necesita conocer ambas: aws_region (Ohio) es la primaria.
  secondary_region = "us-east-1"

  # Nombre de la clave/alias por región. Coincide con aurora_cluster_name de cada capa
  # regional (dmc-lab-drarch-use2 / dmc-lab-drarch-use1) para que sea trazable de un lado a
  # otro sin adivinar.
  kms_key_name = {
    (local.metadata.key.region) = "${local.common_name}-use2"
    secondary                   = "${local.common_name}-use1"
  }
}
