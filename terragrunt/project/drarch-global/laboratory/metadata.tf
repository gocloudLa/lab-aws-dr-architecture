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
}
