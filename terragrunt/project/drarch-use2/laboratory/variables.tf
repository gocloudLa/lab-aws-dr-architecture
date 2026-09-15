variable "global_cluster_identifier" {
  description = "Identificador del aws_rds_global_cluster al que se une este clúster regional."
  type        = string
}

variable "aurora_engine_version" {
  description = "Versión Aurora PostgreSQL, la misma en ambas regiones."
  type        = string
}

variable "aurora_kms_key_arn" {
  description = "ARN de la clave KMS regional para cifrar el clúster. La crea la capa global; el Global Database exige una clave explícita y válida en cada región."
  type        = string
}

variable "secret_suffix" {
  description = "Sufijo aleatorio del nombre del secreto de Aurora. Se genera en la capa global (valor concreto) para no colisionar con un secreto en ventana de borrado tras un destroy+apply."
  type        = string
}

variable "aurora_instance_class" {
  description = "Clase de instancia provisioned. Aurora Global Database no admite burstable (db.t3/db.t4g)."
  type        = string

  validation {
    condition     = !contains(["t3", "t4g"], split(".", var.aurora_instance_class)[1])
    error_message = "aurora_instance_class no puede ser burstable: Aurora Global Database no las admite."
  }
}

variable "is_primary_cluster" {
  description = "true en la región que arranca como writer del Global Database."
  type        = bool
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
  description = "Contraseña del administrador, compartida por ambas regiones porque Aurora replica las credenciales."
  type        = string
  sensitive   = true
}

variable "deletion_protection" {
  description = "Protección contra borrado del clúster Aurora y del repositorio ECR."
  type        = bool
}
