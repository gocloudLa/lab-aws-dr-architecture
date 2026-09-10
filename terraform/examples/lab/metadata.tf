locals {
  # metadata de la Standard Platform. common_name se deja sin definir a propósito: los
  # wrappers de red derivan company-env (gcl-lab) y los de workload company-env-project
  # (gcl-lab-drarch). Fijarlo acá rompería esa separación de capas.
  #
  # key.project se mantiene corto porque los nombres de ALB y de target group tienen un
  # límite de 32 caracteres; el nombre largo del proyecto va en project y en los tags.
  metadata = {
    aws_region    = var.primary_region
    environment   = "Laboratory"
    project       = "aws-dr-architecture"
    public_domain = var.public_domain_name

    key = {
      company = "gcl"
      env     = "lab"
      project = "drarch"
      region  = var.primary_region_key
      layer   = "workload"
    }

    common_tags = {
      company     = "gcl"
      environment = "Laboratory"
      project     = "aws-dr-architecture"
      provisioner = "terraform"
      created-by  = "GoCloud.la"
      demo        = "dr-architecture"
    }
  }
}
