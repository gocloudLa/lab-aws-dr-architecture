variable "primary_region" {
  description = "Región que arranca como writer del Global Database."
  type        = string
}

variable "secondary_region" {
  description = "Región que arranca como réplica (warm standby: corre 1 tarea que falla hasta la promoción)."
  type        = string
}

variable "global_cluster_identifier" {
  description = "Identificador del Aurora Global Database que promueve el plan."
  type        = string
}

variable "global_cluster_arn" {
  description = "ARN del Global Database, para acotar la política del rol de ARC."
  type        = string
}

variable "primary_aurora_cluster_arn" {
  description = "ARN del clúster Aurora de la región primaria."
  type        = string
}

variable "secondary_aurora_cluster_arn" {
  description = "ARN del clúster Aurora de la región secundaria."
  type        = string
}

variable "primary_ecs_cluster_arn" {
  description = "ARN del clúster ECS de la región primaria."
  type        = string
}

variable "primary_ecs_service_arn" {
  description = "ARN del servicio ECS de la región primaria."
  type        = string
}

variable "secondary_ecs_cluster_arn" {
  description = "ARN del clúster ECS de la región secundaria."
  type        = string
}

variable "secondary_ecs_service_arn" {
  description = "ARN del servicio ECS de la región secundaria."
  type        = string
}

variable "primary_alb_dns_name" {
  description = "Hostname del ALB primario, destino del alias Route 53."
  type        = string
}

variable "primary_alb_zone_id" {
  description = "Zona alojada del ALB primario."
  type        = string
}

variable "secondary_alb_dns_name" {
  description = "Hostname del ALB secundario."
  type        = string
}

variable "secondary_alb_zone_id" {
  description = "Zona alojada del ALB secundario."
  type        = string
}

variable "app_hostname" {
  description = "Hostname público canónico que conmuta entre regiones."
  type        = string
}

variable "zone_public" {
  description = "Zona pública Route 53 donde vive el hostname de la aplicación."
  type        = string
}

variable "arc_aurora_behavior" {
  description = "Modo del bloque Aurora de ARC: switchoverOnly evita pérdida esperada; failover la acepta."
  type        = string

  validation {
    condition     = contains(["switchoverOnly", "failover"], var.arc_aurora_behavior)
    error_message = "arc_aurora_behavior debe ser switchoverOnly o failover."
  }
}

variable "arc_recovery_time_objective_minutes" {
  description = "RTO declarado en el plan. Es un objetivo declarativo, no una garantía medida."
  type        = number
}
