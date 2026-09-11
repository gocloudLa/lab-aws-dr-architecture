output "global_cluster_identifier" {
  description = "Identificador del Aurora Global Database al que se unen los clústeres regionales."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN del Global Database; lo consume la política IAM del plan de ARC."
  value       = aws_rds_global_cluster.this.arn
}

output "global_writer_endpoint" {
  description = "Global Writer Endpoint. Sólo diagnóstico: cada Keycloak usa el endpoint de su clúster regional."
  value       = aws_rds_global_cluster.this.endpoint
}

output "aurora_engine_version" {
  description = "Versión del motor, para que las capas regionales usen exactamente la misma."
  value       = var.aurora_engine_version
}

output "database_name" {
  description = "Base PostgreSQL de Keycloak."
  value       = var.database_name
}

output "database_admin_username" {
  description = "Usuario administrador de la base."
  value       = var.database_admin_username
}

output "database_password" {
  description = "Contraseña del usuario administrador, compartida por ambas regiones."
  value       = random_password.database.result
  sensitive   = true
}

output "keycloak_bootstrap_admin_username" {
  description = "Administrador inicial de Keycloak."
  value       = var.keycloak_bootstrap_admin_username
}

output "keycloak_bootstrap_admin_password" {
  description = "Contraseña del administrador inicial de Keycloak."
  value       = random_password.keycloak_admin.result
  sensitive   = true
}

output "common_name" {
  description = "Naming derivado de metadata, para que las capas superiores no lo recalculen."
  value       = local.common_name
}
output "aurora_kms_key_arn_primary" {
  description = "ARN de la clave KMS de la región primaria (Ohio); la capa regional la pasa a Aurora."
  value       = aws_kms_key.primary.arn
}
output "aurora_kms_key_arn_secondary" {
  description = "ARN de la clave KMS de la región secundaria (Virginia); exigida por la réplica cifrada cross-region."
  value       = aws_kms_key.secondary.arn
}
output "secret_suffix" {
  description = "Sufijo aleatorio para el nombre del secreto de Aurora, compartido por ambas regiones (los nombres de clúster ya difieren)."
  value       = random_id.secret_suffix.hex
}
