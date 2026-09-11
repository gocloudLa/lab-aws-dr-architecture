locals {
  zone_public   = local.metadata.key.env == "prd" ? local.metadata.public_domain : "${local.metadata.key.env}.${local.metadata.public_domain}"
  zone_private  = local.metadata.key.env == "prd" ? local.metadata.private_domain : "${local.metadata.key.env}.${local.metadata.private_domain}"
  zone_internal = local.metadata.key.env == "prd" ? local.metadata.internal_domain : "${local.metadata.key.env}.${local.metadata.internal_domain}"

  # Hostname público que conmuta entre regiones.
  app_hostname = "app.${local.zone_public}"

  # Hostname regional de diagnóstico: no conmuta. Un solo label bajo la zona
  # (app-use2, no use2.app) porque el certificado es *.lab.democorp.cloud y el wildcard
  # de ACM cubre exactamente un nivel.
  regional_record_name = "app-${local.region_key}"
  regional_hostname    = "${local.regional_record_name}.${local.zone_public}"
}
