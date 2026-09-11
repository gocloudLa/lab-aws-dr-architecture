# Contrato que consume la capa de ARC y los scripts de scripts/.

output "aws_region" {
  description = "Región de esta capa."
  value       = var.aws_region
}

output "region_key" {
  description = "Sufijo corto de la región."
  value       = var.region_key
}

output "ecs_cluster_name" {
  description = "Clúster ECS donde corre el servicio."
  value       = var.ecs_cluster_name
}

output "ecs_service_name" {
  description = "Servicio ECS de Keycloak en esta región."
  value       = local.ecs_service_name
}

# El wrapper de ECS Service no publica el ARN, así que se compone con el nombre
# determinista que genera. Lo consume el step de escalado del plan de ARC.
output "ecs_service_arn" {
  description = "ARN del servicio ECS de Keycloak en esta región."
  value       = "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${var.ecs_cluster_name}/${local.ecs_service_name}"
}

output "ecs_cluster_arn" {
  description = "ARN del clúster ECS."
  value       = "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.ecs_cluster_name}"
}

output "regional_app_url" {
  description = "URL regional de diagnóstico; no conmuta."
  value       = "https://${var.regional_hostname}"
}

output "ecs_desired_count" {
  description = "Tareas configuradas por Terraform en esta región."
  value       = var.ecs_desired_count
}
