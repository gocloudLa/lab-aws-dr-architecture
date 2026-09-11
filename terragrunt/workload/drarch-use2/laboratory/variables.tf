variable "aws_region" {
  description = "Región AWS de esta capa."
  type        = string
}

variable "region_key" {
  description = "Sufijo corto de la región; por ejemplo use2 o use1."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2,4}[0-9]$", var.region_key))
    error_message = "region_key debe seguir el formato corto de la Standard Platform, por ejemplo use2 o use1."
  }
}

variable "vpc_name" {
  description = "Tag Name de la VPC existente. wrapper-ecs-service resuelve la red por tag, no por ID."
  type        = string
}

variable "app_subnet_name" {
  description = "Patrón del tag Name de las subredes privadas donde corren las tareas ECS."
  type        = string
}

variable "ecs_cluster_name" {
  description = "Clúster ECS creado por la capa project."
  type        = string
}

variable "alb_name" {
  description = "ALB creado por la capa project; el wrapper lo resuelve por nombre."
  type        = string
}

variable "ecr_repository_url" {
  description = "Repositorio ECR regional donde está publicada la imagen."
  type        = string
}

variable "container_image_tag" {
  description = "Etiqueta inmutable publicada en el ECR antes de habilitar el servicio."
  type        = string
}

variable "ecs_desired_count" {
  description = "Tareas Keycloak en esta región. Warm standby: ambas regiones conservan 1; la reader no recibe tráfico hasta que ARC promueve su Aurora."
  type        = number

  validation {
    condition     = var.ecs_desired_count >= 0 && floor(var.ecs_desired_count) == var.ecs_desired_count
    error_message = "ecs_desired_count debe ser un entero no negativo."
  }
}

variable "db_host" {
  description = "Endpoint del clúster Aurora de esta región. Es el único DB_HOST que recibe Keycloak acá."
  type        = string
}

variable "database_name" {
  description = "Base PostgreSQL de Keycloak."
  type        = string
}

variable "database_admin_username" {
  description = "Usuario administrador de la base."
  type        = string
}

variable "database_password" {
  description = "Contraseña del administrador de la base."
  type        = string
  sensitive   = true
}

variable "keycloak_bootstrap_admin_username" {
  description = "Administrador inicial de Keycloak."
  type        = string
}

variable "keycloak_bootstrap_admin_password" {
  description = "Contraseña del administrador inicial de Keycloak."
  type        = string
  sensitive   = true
}

variable "app_hostname" {
  description = "Hostname público canónico que conmuta entre regiones."
  type        = string
}

variable "regional_hostname" {
  description = "FQDN regional de diagnóstico, que siempre resuelve al ALB de esta región."
  type        = string
}
