output "arc_plan_arn" {
  description = "Plan de ARC Region switch que orquesta la conmutación."
  value       = aws_arcregionswitch_plan.this.arn
}

output "arc_plan_name" {
  description = "Nombre del plan de ARC."
  value       = aws_arcregionswitch_plan.this.name
}

output "arc_aurora_behavior" {
  description = "Modo configurado del bloque Aurora del plan."
  value       = var.arc_aurora_behavior
}

output "app_dns_name" {
  description = "Hostname público que conmuta entre regiones."
  value       = var.app_hostname
}

output "public_zone_id" {
  description = "Zona pública donde viven los registros FAILOVER."
  value       = data.aws_route53_zone.public.zone_id
}

output "region_roles" {
  description = "Roles iniciales; después de una conmutación consultar el estado real de Aurora."
  value = {
    primary   = { region = var.primary_region, initial_role = "writer" }
    secondary = { region = var.secondary_region, initial_role = "reader" }
  }
}

output "arc_execution_role_arn" {
  description = "Rol que asume ARC Region switch durante la ejecución."
  value       = aws_iam_role.arc.arn
}
