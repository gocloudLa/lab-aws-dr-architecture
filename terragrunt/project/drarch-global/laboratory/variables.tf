variable "aurora_engine_version" {
  description = "Versión Aurora PostgreSQL disponible en ambas regiones con soporte Global Database."
  type        = string
}

variable "database_name" {
  description = "Base PostgreSQL que crea el clúster primario."
  type        = string
}

variable "database_admin_username" {
  description = "Usuario administrador de la base que usa Keycloak."
  type        = string
  default     = "keycloak_admin"
}

variable "keycloak_bootstrap_admin_username" {
  description = "Administrador inicial de Keycloak."
  type        = string
  default     = "admin"
}

variable "deletion_protection" {
  description = "Protección contra borrado del Global Database."
  type        = bool
}
