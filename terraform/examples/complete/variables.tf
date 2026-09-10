variable "primary_region" {
  description = "Región que arranca como writer del Global Database."
  type        = string
  default     = "us-east-2"
}

variable "secondary_region" {
  description = "Región que arranca como réplica y warm standby."
  type        = string
  default     = "us-east-1"
}

variable "primary_region_key" {
  description = "Sufijo corto de la región primaria, usado en los nombres de recurso."
  type        = string
  default     = "use2"
}

variable "secondary_region_key" {
  description = "Sufijo corto de la región secundaria, usado en los nombres de recurso."
  type        = string
  default     = "use1"
}

variable "primary_vpc_cidr" {
  description = "CIDR de la VPC primaria. No debe solaparse con el de la secundaria: hay peering entre ambas."
  type        = string
  default     = "10.20.0.0/16"
}

variable "secondary_vpc_cidr" {
  description = "CIDR de la VPC secundaria."
  type        = string
  default     = "10.30.0.0/16"
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
  description = "ARN de un certificado ACM de la región primaria que cubra app y <key>.app bajo el dominio."
  type        = string
}

variable "certificate_arn_secondary" {
  description = "ARN de un certificado ACM de la región secundaria que cubra app y <key>.app bajo el dominio."
  type        = string
}

variable "container_image_tag" {
  description = "Etiqueta inmutable publicada en ambos ECR antes de habilitar los servicios."
  type        = string
  default     = "bootstrap-required"
}

variable "ecs_desired_count" {
  description = "Tareas Keycloak por región: 0 durante el bootstrap y 1 con la demo habilitada."
  type        = number
  default     = 0
}

variable "arc_aurora_behavior" {
  description = "Modo del bloque Aurora de ARC: switchoverOnly o failover."
  type        = string
  default     = "switchoverOnly"
}

variable "deletion_protection" {
  description = "Protección contra borrado de los clústeres Aurora."
  type        = bool
  default     = true
}
