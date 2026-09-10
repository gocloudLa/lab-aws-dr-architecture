# Sin wrapper en la Standard Platform: los records de failover se asocian a los health
# checks que genera ARC, y ningún wrapper expone esa combinación. Los hostnames
# regionales de diagnóstico sí los crea wrapper-alb dentro del módulo por región.

data "aws_arcregionswitch_route53_health_checks" "traffic" {
  provider = aws.primary

  plan_arn = aws_arcregionswitch_plan.this.arn
}

locals {
  app_health_check_matches = {
    for region in [var.primary_region, var.secondary_region] : region => [
      for check in data.aws_arcregionswitch_route53_health_checks.traffic.health_checks : check.health_check_id
      if check.region == region && check.hosted_zone_id == var.public_zone_id && trimsuffix(check.record_name, ".") == local.app_record_name
    ]
  }

  app_health_checks = {
    for region, matches in local.app_health_check_matches : region => try(matches[0], null)
  }
}

# evaluate_target_health queda en false a propósito: sólo ARC decide la conmutación, así
# el orden promoción-de-Aurora antes que DNS no lo puede alterar Route 53 por su cuenta.
resource "aws_route53_record" "application_primary" {
  provider = aws.primary

  zone_id         = var.public_zone_id
  name            = local.app_record_name
  type            = "A"
  set_identifier  = var.primary_region
  health_check_id = local.app_health_checks[var.primary_region]

  failover_routing_policy { type = "PRIMARY" }

  alias {
    name                   = module.primary.alb_dns_name
    zone_id                = module.primary.alb_zone_id
    evaluate_target_health = false
  }

  lifecycle {
    precondition {
      condition     = length(local.app_health_check_matches[var.primary_region]) == 1
      error_message = "ARC debe exponer exactamente un health check para ${local.app_record_name} en ${var.primary_region}."
    }
  }
}

resource "aws_route53_record" "application_secondary" {
  provider = aws.primary

  zone_id         = var.public_zone_id
  name            = local.app_record_name
  type            = "A"
  set_identifier  = var.secondary_region
  health_check_id = local.app_health_checks[var.secondary_region]

  failover_routing_policy { type = "SECONDARY" }

  alias {
    name                   = module.secondary.alb_dns_name
    zone_id                = module.secondary.alb_zone_id
    evaluate_target_health = false
  }

  lifecycle {
    precondition {
      condition     = length(local.app_health_check_matches[var.secondary_region]) == 1
      error_message = "ARC debe exponer exactamente un health check para ${local.app_record_name} en ${var.secondary_region}."
    }
  }
}
