data "aws_partition" "current" {
  provider = aws.primary
}

locals {
  # Mismo nombre que derivan los wrappers de la capa de workload, para que los recursos
  # sin wrapper (ARC, IAM, DNS) queden alineados con el estándar de naming.
  common_name = join("-", [
    var.metadata.key.company,
    var.metadata.key.env,
    var.metadata.key.project
  ])

  app_record_name = "app.${var.public_domain_name}"

  # Hostnames de diagnóstico: no conmutan, sirven para ver cada región por separado.
  regional_records = {
    (var.primary_region_key)   = "${var.primary_region_key}.app"
    (var.secondary_region_key) = "${var.secondary_region_key}.app"
  }

  regional_hostnames = {
    for key, record in local.regional_records : key => "${record}.${var.public_domain_name}"
  }
}
