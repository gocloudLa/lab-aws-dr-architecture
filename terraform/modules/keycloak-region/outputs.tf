# El wrapper de Aurora no publica outputs, así que el ARN se compone con el nombre
# determinista que genera (${common_name}-${clave}). Lo consume el plan de ARC.
output "aurora_cluster_arn" {
  description = "ARN del clúster Aurora regional."
  value       = "arn:${data.aws_partition.current.partition}:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster:${local.aurora_cluster_name}"
}

output "alb_dns_name" {
  description = "Hostname del ALB regional, destino de los alias Route 53."
  value       = module.alb.alb[var.region_key].dns_name
}

output "alb_zone_id" {
  description = "Zona alojada del ALB regional, requerida por los alias Route 53."
  value       = module.alb.alb[var.region_key].zone_id
}

output "ecr_repository_url" {
  description = "Repositorio donde publicar la imagen de Keycloak de esta región."
  value       = local.ecr_repository_url
}

output "ecs_cluster_name" {
  description = "Clúster ECS regional."
  value       = local.ecs_cluster_name
}

output "ecs_service_name" {
  description = "Servicio ECS de Keycloak en esta región."
  value       = local.ecs_service_name
}
