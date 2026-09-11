# Contrato que consumen los scripts de scripts/. Mantener los nombres.

output "app_dns_name" {
  description = "Hostname público que conmuta entre regiones."
  value       = module.dr_architecture.app_dns_name
}

output "regional_app_urls" {
  description = "URLs de diagnóstico por región; no conmutan."
  value       = module.dr_architecture.regional_app_urls
}

output "ecr_repository_urls" {
  description = "Repositorios donde publicar la imagen de Keycloak."
  value       = module.dr_architecture.ecr_repository_urls
}

output "ecs_cluster_names" {
  description = "Clústeres ECS por región."
  value       = module.dr_architecture.ecs_cluster_names
}

output "ecs_service_names" {
  description = "Servicios ECS de Keycloak por región."
  value       = module.dr_architecture.ecs_service_names
}

output "arc_plan_arn" {
  description = "Plan de ARC Region switch."
  value       = module.dr_architecture.arc_plan_arn
}

output "arc_aurora_behavior" {
  description = "Modo configurado del bloque Aurora del plan."
  value       = module.dr_architecture.arc_aurora_behavior
}

output "region_roles" {
  description = "Roles iniciales; después de una conmutación consultar el estado real de Aurora."
  value       = module.dr_architecture.region_roles
}

output "global_cluster_identifier" {
  description = "Identificador del Aurora Global Database."
  value       = module.dr_architecture.global_cluster_identifier
}

output "global_writer_endpoint" {
  description = "Hostname del Aurora Global Database. Sólo diagnóstico: cada Keycloak usa el endpoint de su propio clúster regional, no este valor."
  value       = module.dr_architecture.global_writer_endpoint
}

output "aurora_engine_version" {
  description = "Versión Aurora PostgreSQL aplicada a los dos clústeres regionales."
  value       = module.dr_architecture.aurora_engine_version
}

output "aurora_instance_class" {
  description = "Clase de instancia provisioned del clúster Aurora, igual en ambas regiones."
  value       = module.dr_architecture.aurora_instance_class
}
