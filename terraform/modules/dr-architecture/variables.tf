variable "metadata" {
  description = "Metadata de la Standard Platform. No debe traer common_name: la capa de red deriva company-env y la de workload company-env-project."
  type        = any
}

variable "primary_region" {
  description = "Región que arranca como writer del Global Database."
  type        = string
}

variable "secondary_region" {
  description = "Región que arranca como réplica y warm standby."
  type        = string
}

variable "primary_region_key" {
  description = "Sufijo corto de la región primaria; por ejemplo use2."
  type        = string
}

variable "secondary_region_key" {
  description = "Sufijo corto de la región secundaria; por ejemplo use1."
  type        = string
}

variable "primary_network" {
  description = "Red de la región primaria. El ALB y Aurora reciben IDs de subred explícitos; sólo wrapper-ecs-service resuelve por tag Name, porque es lo único que acepta."
  type = object({
    vpc_name                    = string
    app_subnet_name             = string
    default_security_group_name = string
    public_subnet_ids           = list(string)
    database_subnet_ids         = list(string)
    app_cidr_blocks             = list(string)
  })
}

variable "secondary_network" {
  description = "Red existente de la región secundaria, con el mismo contrato que primary_network."
  type = object({
    vpc_name                    = string
    app_subnet_name             = string
    default_security_group_name = string
    public_subnet_ids           = list(string)
    database_subnet_ids         = list(string)
    app_cidr_blocks             = list(string)
  })
}

variable "public_zone_id" {
  description = "ID de una zona pública Route 53 preexistente."
  type        = string
}

variable "public_domain_name" {
  description = "Dominio raíz de la zona pública, sin punto final; por ejemplo demo.example.com."
  type        = string
}

variable "certificate_arn_primary" {
  description = "ARN de un certificado ACM de la región primaria que cubra el hostname público y el regional."
  type        = string
}

variable "certificate_arn_secondary" {
  description = "ARN de un certificado ACM de la región secundaria que cubra el hostname público y el regional."
  type        = string
}

variable "database_name" {
  description = "Base PostgreSQL creada inicialmente."
  type        = string
  default     = "keycloak"
}

variable "database_admin_username" {
  description = "Usuario de base usado por Keycloak; simplificación explícita de la demo."
  type        = string
  default     = "keycloak_admin"
}

variable "aurora_engine_version" {
  description = "Versión Aurora PostgreSQL disponible en ambas regiones; confirmar con el preflight antes de apply."
  type        = string
  default     = "16.14"
}

variable "aurora_instance_class" {
  description = <<-EOT
    Clase de instancia provisioned del clúster Aurora, simétrica en ambas regiones.
    Aurora Global Database no admite clases burstable (db.t3/db.t4g); usar una
    memory-optimized (familia db.r*), confirmando disponibilidad en ambas regiones con
    aws rds describe-orderable-db-instance-options antes de aplicar.
  EOT
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = !contains(["t3", "t4g"], split(".", var.aurora_instance_class)[1])
    error_message = "aurora_instance_class no puede ser una clase burstable (db.t3/db.t4g): Aurora Global Database no las admite."
  }
}

variable "container_image_tag" {
  description = "Etiqueta inmutable publicada en ambos ECR antes de habilitar los servicios."
  type        = string
  default     = "bootstrap-required"
}

variable "ecs_desired_count" {
  description = <<-EOT
    Tareas Keycloak en la región primaria: 0 durante bootstrap y al menos 1 después de
    publicar la imagen. La región secundaria es pilot light y siempre arranca en 0; el
    plan de ARC la escala durante la conmutación (ver arc.tf), después de promover Aurora
    y antes de mover el DNS.
  EOT
  type        = number
  default     = 0

  validation {
    condition     = var.ecs_desired_count >= 0 && floor(var.ecs_desired_count) == var.ecs_desired_count
    error_message = "ecs_desired_count debe ser un entero no negativo."
  }
}

variable "keycloak_bootstrap_admin_username" {
  description = "Administrador inicial de Keycloak."
  type        = string
  default     = "admin"
}

variable "arc_aurora_behavior" {
  description = "Modo normal de ARC: switchoverOnly evita pérdida esperada; failover acepta posible pérdida."
  type        = string
  default     = "switchoverOnly"

  validation {
    condition     = contains(["switchoverOnly", "failover"], var.arc_aurora_behavior)
    error_message = "arc_aurora_behavior debe ser switchoverOnly o failover."
  }
}

variable "arc_recovery_time_objective_minutes" {
  description = "RTO declarado en el plan de ARC. Es un objetivo declarativo, no una garantía medida."
  type        = number
  default     = 45
}

variable "deletion_protection" {
  description = "Protección contra borrado de los clústeres Aurora."
  type        = bool
  default     = true
}
