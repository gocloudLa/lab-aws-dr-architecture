locals {
  metadata = {
    aws_region      = var.primary_region
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
      layer   = "workload"
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

  common_name_prefix = join("-", [
    local.metadata.key.company,
    local.metadata.key.env
  ])

  common_name = join("-", [
    local.common_name_prefix,
    local.metadata.key.project
  ])
}
