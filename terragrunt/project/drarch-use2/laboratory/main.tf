locals {
  metadata_layer = merge(local.metadata, {
    common_tags = local.metadata.common_tags
  })
}

/*----------------------------------------------------------------------*/
/* ECR | Registro regional de la imagen de Keycloak                     */
/*----------------------------------------------------------------------*/

# Cada región publica desde su propio repositorio: durante una conmutación la región
# destino no debe depender de un registro alojado en la región caída.
module "ecr" {
  source  = "gocloudLa/wrapper-ecr/aws"
  version = "0.1.1"

  metadata = local.metadata_layer

  ecr_parameters = {
    (local.ecr_repository_key) = {
      repository_image_tag_mutability = "IMMUTABLE"
      repository_image_scan_on_push   = true
      repository_force_delete         = !var.deletion_protection

      repository_lifecycle_policy = jsonencode({
        rules = [{
          rulePriority = 1
          description  = "Conservar las ultimas 10 imagenes"
          selection = {
            tagStatus   = "any"
            countType   = "imageCountMoreThan"
            countNumber = 10
          }
          action = { type = "expire" }
        }]
      })
    }
  }
}

/*----------------------------------------------------------------------*/
/* Aurora | Clúster regional del Global Database                        */
/*----------------------------------------------------------------------*/

module "aurora" {
  source  = "gocloudLa/wrapper-rds-aurora/aws"
  version = "1.5.0"

  metadata = local.metadata_layer

  rds_aurora_parameters = {
    (local.region_key) = {
      engine         = "aurora-postgresql"
      engine_version = var.aurora_engine_version
      port           = 5432

      # El clúster se une al Global Database creado en la capa global. En la región
      # secundaria is_primary_cluster=false deja que Aurora herede base y credenciales.
      global_cluster_identifier = var.global_cluster_identifier
      is_primary_cluster        = var.is_primary_cluster
      database_name             = var.database_name
      master_username           = var.database_admin_username
      master_password           = var.database_password

      subnets = data.aws_subnets.database.ids

      cluster_parameter_group_family = "aurora-postgresql${split(".", var.aurora_engine_version)[0]}"
      db_parameter_group_family      = "aurora-postgresql${split(".", var.aurora_engine_version)[0]}"

      # Instancia provisioned, no Serverless v2 (decisión explícita de este lab).
      instances = {
        1 = {
          instance_class      = var.aurora_instance_class
          promotion_tier      = 0
          publicly_accessible = false
        }
      }

      # Clave regional explícita: el Global Database la exige en cada región. La crea la capa
      # global y llega como input concreto, no como un valor unknown que rompería el plan.
      storage_encrypted       = true
      kms_key_id              = var.aurora_kms_key_arn
      apply_immediately       = true
      backup_retention_period = var.is_primary_cluster ? 7 : 1
      deletion_protection     = var.deletion_protection
      skip_final_snapshot     = !var.deletion_protection

      # Sólo el CIDR de las subredes de aplicación de esta región: cada Keycloak conecta a
      # su propio clúster, así que no hace falta abrir el CIDR remoto ni peering.
      ingress_with_cidr_blocks = [{
        rule        = "postgresql-tcp"
        cidr_blocks = join(",", local.app_cidr_blocks)
        description = "PostgreSQL desde las subredes de aplicacion de esta region"
      }]

      # Nombre con sufijo aleatorio para no colisionar con un secreto en ventana de borrado, y
      # recovery_window_in_days=0 para que el destroy del lab lo elimine de inmediato sin
      # dejar un huérfano que bloquee el próximo apply.
      secret = {
        name                    = "rds-${local.aurora_cluster_name}-${var.secret_suffix}"
        recovery_window_in_days = 0
      }
    }
  }
}

/*----------------------------------------------------------------------*/
/* ALB | Entrada pública regional                                       */
/*----------------------------------------------------------------------*/

module "alb" {
  source  = "gocloudLa/wrapper-alb/aws"
  version = "1.3.1"

  metadata = local.metadata_layer

  alb_parameters = {
    (local.region_key) = {
      internal = false
      subnets  = data.aws_subnets.public.ids

      # Descarta cabeceras mal formadas antes de reenviarlas. Keycloak confía en
      # X-Forwarded-*, así que dejar pasar cabeceras inválidas sería un riesgo real.
      drop_invalid_header_fields = true

      listeners = {
        80 = {
          port     = 80
          protocol = "HTTP"
          redirect = {
            port        = "443"
            protocol    = "HTTPS"
            status_code = "HTTP_301"
          }
        }
        # La acción por defecto responde 503: sólo la regla que publica el wrapper de
        # ECS Service reenvía tráfico, así el ALB no expone un backend inexistente.
        443 = {
          port            = 443
          protocol        = "HTTPS"
          certificate_arn = data.aws_acm_certificate.this.arn
          ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
          action_type     = "fixed-response"
          fixed_response = {
            content_type = "text/plain"
            message_body = "Sin backend disponible en esta region"
            status_code  = "503"
          }
        }
      }

      ingress_with_cidr_blocks = [
        {
          rule        = "https-443-tcp"
          cidr_blocks = "0.0.0.0/0"
          description = "HTTPS desde internet"
        },
        {
          # Sin tildes ni signos fuera de [0-9A-Za-z_ .:/()#,@[]+=&;{}!$*-]: AWS rechaza la
          # descripción de la regla del security group si no matchea esa regex.
          rule        = "http-80-tcp"
          cidr_blocks = "0.0.0.0/0"
          description = "HTTP desde internet, solo para redirigir a HTTPS"
        }
      ]

      # Hostname regional de diagnóstico: no conmuta, siempre apunta a este ALB.
      dns_records = {
        (local.regional_record_name) = {
          zone_name    = local.zone_public
          private_zone = false
        }
      }
    }
  }
}

/*----------------------------------------------------------------------*/
/* ECS | Clúster regional                                               */
/*----------------------------------------------------------------------*/

# El servicio vive en la capa workload: necesita el ALB, el ECR y el endpoint de Aurora ya
# creados, y es justamente la dependencia que no se puede expresar dentro de un solo state.
module "ecs" {
  source  = "gocloudLa/wrapper-ecs/aws"
  version = "1.0.3"

  metadata = local.metadata_layer

  ecs_parameters = {
    (local.ecs_cluster_key) = {
      cluster_capacity_providers = ["FARGATE"]
      default_capacity_provider_strategy = {
        FARGATE = { weight = 100 }
      }
      # Container Insights deshabilitado: el wrapper lo activa por defecto, pero para el
      # lab no se necesita esa telemetría (ni su costo de CloudWatch).
      cluster_settings = [{ name = "containerInsights", value = "disabled" }]
    }
  }
}

/*----------------------------------------------------------------------*/
/* Endpoint del clúster | Lo consume la capa workload como DB_HOST      */
/*----------------------------------------------------------------------*/

# El wrapper de Aurora no publica outputs, así que el endpoint se lee del clúster creado.
data "aws_rds_cluster" "this" {
  cluster_identifier = local.aurora_cluster_name

  depends_on = [module.aurora]
}
