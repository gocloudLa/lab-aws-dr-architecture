# Contrato hacia las capas workload y ARC. Todos estos valores son concretos una vez que
# esta capa aplicó, que es exactamente lo que permite a las capas superiores planificar.

output "aws_region" {
  description = "Región de esta capa."
  value       = local.metadata.aws_region
}

output "region_key" {
  description = "Sufijo corto de la región."
  value       = local.region_key
}

output "common_name" {
  description = "Naming derivado de metadata."
  value       = local.common_name
}

output "common_name_prefix" {
  description = "Prefijo company-env, que es el tag Name de la VPC."
  value       = local.common_name_prefix
}

output "vpc_id" {
  description = "VPC donde vive el stack regional."
  value       = data.aws_vpc.this.id
}

output "app_subnet_name" {
  description = "Patrón de tag de las subredes privadas; wrapper-ecs-service sólo acepta nombre, no IDs."
  value       = "${local.common_name_prefix}-private*"
}

output "app_cidr_blocks" {
  description = "CIDR de las subredes de aplicación, habilitados hacia PostgreSQL."
  value       = local.app_cidr_blocks
}

output "aurora_cluster_identifier" {
  description = "Identificador del clúster Aurora regional."
  value       = local.aurora_cluster_name
}

output "aurora_cluster_arn" {
  description = "ARN del clúster Aurora regional; lo consume el plan de ARC."
  value       = data.aws_rds_cluster.this.arn
}

output "aurora_cluster_endpoint" {
  description = "Endpoint del clúster Aurora local. Es el DB_HOST de Keycloak en esta región."
  value       = data.aws_rds_cluster.this.endpoint
}

output "ecr_repository_name" {
  description = "Repositorio ECR regional."
  value       = local.ecr_repository_name
}

output "ecr_repository_url" {
  description = "URL del repositorio donde publicar la imagen de Keycloak."
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${local.metadata.aws_region}.amazonaws.com/${local.ecr_repository_name}"
}

output "ecs_cluster_name" {
  description = "Clúster ECS regional."
  value       = local.ecs_cluster_name
}

output "ecs_cluster_arn" {
  description = "ARN del clúster ECS; lo consume el step de escalado del plan de ARC."
  value       = "arn:${data.aws_partition.current.partition}:ecs:${local.metadata.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${local.ecs_cluster_name}"
}

# wrapper-alb no publica el nombre del ALB, así que se deriva del ARN del listener 443.
# Formato: arn:...:listener/app/<nombre-alb>/<id-alb>/<id-listener>. Además de dar el
# nombre exacto, obliga a que el listener exista antes de que la capa workload lo busque.
output "alb_name" {
  description = "Nombre del ALB regional; wrapper-ecs-service lo resuelve por nombre."
  value       = split("/", module.alb.alb[local.region_key].listeners["443"].arn)[2]
}

output "alb_dns_name" {
  description = "Hostname del ALB regional, destino de los alias Route 53."
  value       = module.alb.alb[local.region_key].dns_name
}

output "alb_zone_id" {
  description = "Zona alojada del ALB regional, requerida por los alias Route 53."
  value       = module.alb.alb[local.region_key].zone_id
}

output "app_hostname" {
  description = "Hostname público canónico que conmuta entre regiones."
  value       = local.app_hostname
}

output "regional_hostname" {
  description = "FQDN regional de diagnóstico, siempre apunta a este ALB."
  value       = local.regional_hostname
}

output "zone_public" {
  description = "Zona pública derivada del entorno."
  value       = local.zone_public
}

output "aurora_instance_class" {
  description = "Clase de instancia provisioned del clúster Aurora; el preflight valida que exista en la región."
  value       = var.aurora_instance_class
}
