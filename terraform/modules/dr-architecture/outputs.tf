# Las claves de los outputs por región usan la región AWS con guiones bajos porque los
# scripts de la demo indexan por región normalizada.

output "region_roles" {
  description = "Roles iniciales exactos; después de una conmutación consultar el estado real de Aurora."
  value = {
    primary   = { region = var.primary_region, key = var.primary_region_key, initial_role = "writer" }
    secondary = { region = var.secondary_region, key = var.secondary_region_key, initial_role = "reader" }
  }
}

output "app_dns_name" {
  description = "Hostname público que conmuta entre regiones."
  value       = local.app_record_name
}

output "regional_app_urls" {
  description = "URLs de diagnóstico por región; no conmutan."
  value = {
    (replace(var.primary_region, "-", "_"))   = "https://${local.regional_hostnames[var.primary_region_key]}"
    (replace(var.secondary_region, "-", "_")) = "https://${local.regional_hostnames[var.secondary_region_key]}"
  }
}

output "ecr_repository_urls" {
  description = "Repositorios donde publicar la imagen de Keycloak antes de habilitar los servicios."
  value = {
    (replace(var.primary_region, "-", "_"))   = module.primary.ecr_repository_url
    (replace(var.secondary_region, "-", "_")) = module.secondary.ecr_repository_url
  }
}

output "ecs_cluster_names" {
  description = "Clústeres ECS por región."
  value = {
    (replace(var.primary_region, "-", "_"))   = module.primary.ecs_cluster_name
    (replace(var.secondary_region, "-", "_")) = module.secondary.ecs_cluster_name
  }
}

output "ecs_service_names" {
  description = "Servicios ECS de Keycloak por región."
  value = {
    (replace(var.primary_region, "-", "_"))   = module.primary.ecs_service_name
    (replace(var.secondary_region, "-", "_")) = module.secondary.ecs_service_name
  }
}

output "global_cluster_identifier" {
  description = "Identificador del Aurora Global Database."
  value       = aws_rds_global_cluster.this.id
}

output "global_writer_endpoint" {
  description = "Hostname estable que Aurora reapunta al clúster writer vigente."
  value       = aws_rds_global_cluster.this.endpoint
}

output "arc_plan_arn" {
  description = "Plan de ARC Region switch que orquesta la conmutación."
  value       = aws_arcregionswitch_plan.this.arn
}

output "arc_aurora_behavior" {
  description = "Modo configurado del bloque Aurora del plan."
  value       = var.arc_aurora_behavior
}
