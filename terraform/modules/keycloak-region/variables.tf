variable "metadata" {
  description = "Metadata de la Standard Platform. No debe traer common_name: cada wrapper lo deriva de key.company/env/project."
  type        = any
}

variable "region_key" {
  description = "Sufijo corto de la región, usado como clave de recurso en los wrappers; por ejemplo use2 o use1."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2,4}[0-9]$", var.region_key))
    error_message = "region_key debe seguir el formato corto de la Standard Platform, por ejemplo use2 o use1."
  }
}

variable "aws_region" {
  description = "Región AWS donde se despliegan los recursos de esta instancia del módulo."
  type        = string
}

variable "vpc_name" {
  description = "Tag Name de la VPC existente. Los wrappers resuelven la red por tag, no por ID."
  type        = string
}

variable "app_subnet_name" {
  description = "Patrón del tag Name de las subredes privadas donde corren las tareas ECS. Admite comodín, por ejemplo gcl-lab-private*."
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs de las subredes públicas donde se publica el ALB. Se pasan explícitos, no por tag: así la dependencia con la red es una referencia real."
  type        = list(string)
}

variable "database_subnet_ids" {
  description = "IDs de las subredes donde vive el clúster Aurora."
  type        = list(string)
}

variable "default_security_group_name" {
  description = "Tag Name del security group por defecto de la VPC. El wrapper de Aurora lo resuelve siempre, incluso sin usar sus features de gestión de base."
  type        = string
}

variable "app_cidr_blocks" {
  description = "CIDR de las subredes de aplicación locales, habilitados hacia PostgreSQL. Cada región sólo permite su propio tráfico: no hace falta peering porque ningún Keycloak cruza de región."
  type        = list(string)
}

variable "certificate_arn" {
  description = "ARN de un certificado ACM emitido en esta región que cubra el hostname público y el regional."
  type        = string
}

variable "public_domain_name" {
  description = "Dominio de la zona pública Route 53, sin punto final."
  type        = string
}

variable "app_hostname" {
  description = "Hostname público canónico de Keycloak, el que conmuta entre regiones."
  type        = string
}

variable "regional_record_name" {
  description = "Nombre relativo del hostname regional de diagnóstico dentro de la zona; por ejemplo ohio.app."
  type        = string
}

variable "regional_hostname" {
  description = "FQDN del hostname regional de diagnóstico, que siempre resuelve al ALB de esta región."
  type        = string
}

variable "global_cluster_identifier" {
  description = "Identificador del aws_rds_global_cluster al que se une el clúster regional."
  type        = string
}

variable "is_primary" {
  description = "true en la región que arranca como writer del Global Database; false en la que arranca como réplica."
  type        = bool
}

variable "database_name" {
  description = "Base PostgreSQL creada por el clúster primario."
  type        = string
}

variable "database_admin_username" {
  description = "Usuario administrador de la base que usa Keycloak."
  type        = string
}

variable "database_password" {
  description = "Contraseña del usuario administrador, compartida por ambas regiones porque Aurora replica las credenciales."
  type        = string
  sensitive   = true
}

variable "aurora_engine_version" {
  description = "Versión Aurora PostgreSQL disponible en ambas regiones."
  type        = string
}

variable "aurora_instance_class" {
  description = "Clase de instancia provisioned del clúster Aurora en esta región. Aurora Global Database no admite clases burstable (db.t3/db.t4g); la memory-optimized más chica suele ser db.r6g.large o db.r5.large, según disponibilidad regional."
  type        = string
}

variable "deletion_protection" {
  description = "Protección contra borrado del clúster Aurora y del repositorio ECR."
  type        = bool
}

variable "container_image_tag" {
  description = "Etiqueta inmutable publicada en el ECR de esta región antes de habilitar el servicio."
  type        = string
}

variable "ecs_desired_count" {
  description = "Tareas Keycloak en esta región: 0 durante el bootstrap sin imagen y 1 con la demo habilitada."
  type        = number
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
