/*----------------------------------------------------------------------*/
/* ECR | Registro regional de la imagen de Keycloak                     */
/*----------------------------------------------------------------------*/

# Cada región publica desde su propio repositorio: durante una conmutación la región
# destino no debe depender de un registro alojado en la región caída.
module "ecr" {
  source  = "gocloudLa/wrapper-ecr/aws"
  version = "0.1.1"

  metadata = local.metadata

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

  metadata = local.metadata

  rds_aurora_parameters = {
    (var.region_key) = {
      # El wrapper resuelve VPC y security group por tag; sin vpc_name explícito cae al
      # default derivado de metadata (company-env), que no coincide con una VPC ya
      # existente con otro nombre, como la de este laboratorio.
      vpc_name       = var.vpc_name
      engine         = "aurora-postgresql"
      engine_version = var.aurora_engine_version
      port           = 5432

      # El clúster se une al Global Database creado en el módulo raíz. En la región
      # secundaria is_primary_cluster=false deja que Aurora herede base y credenciales.
      global_cluster_identifier = var.global_cluster_identifier
      is_primary_cluster        = var.is_primary
      database_name             = var.database_name
      master_username           = var.database_admin_username
      master_password           = var.database_password

      subnets                     = var.database_subnet_ids
      default_security_group_name = var.default_security_group_name

      cluster_parameter_group_family = local.aurora_parameter_group
      db_parameter_group_family      = local.aurora_parameter_group

      # Instancia provisioned, no Serverless v2: Aurora Global Database no admite clases
      # burstable (db.t3/db.t4g) como instancia de un clúster miembro, así que la más
      # chica válida es una memory-optimized; instance_class llega desde la variable de
      # laboratorio, no hardcodeada, para poder ajustarla sin tocar el módulo.
      instances = {
        1 = {
          instance_class      = var.aurora_instance_class
          promotion_tier      = 0
          publicly_accessible = false
        }
      }

      storage_encrypted       = true
      apply_immediately       = true
      backup_retention_period = var.is_primary ? 7 : 1
      deletion_protection     = var.deletion_protection
      skip_final_snapshot     = !var.deletion_protection

      ingress_with_cidr_blocks = [{
        rule        = "postgresql-tcp"
        cidr_blocks = local.database_ingress_cidrs
        description = "PostgreSQL desde las subredes de aplicacion de ambas regiones"
      }]
    }
  }
}

/*----------------------------------------------------------------------*/
/* ALB | Entrada pública regional                                       */
/*----------------------------------------------------------------------*/

module "alb" {
  source  = "gocloudLa/wrapper-alb/aws"
  version = "1.3.1"

  metadata = local.metadata

  alb_parameters = {
    (var.region_key) = {
      # Mismo motivo que en el bloque de Aurora: sin vpc_name explícito el wrapper cae a
      # su default derivado de metadata, que no coincide con una VPC ya existente.
      vpc_name = var.vpc_name
      internal = false
      subnets  = var.public_subnet_ids

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
          certificate_arn = var.certificate_arn
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
          rule        = "http-80-tcp"
          cidr_blocks = "0.0.0.0/0"
          # Sin tildes ni signos fuera de [0-9A-Za-z_ .:/()#,@[]+=&;{}!$*-]: AWS rechaza la
          # descripción de la regla del security group si no matchea esa regex.
          description = "HTTP desde internet, solo para redirigir a HTTPS"
        }
      ]

      # Hostname regional de diagnóstico: no conmuta, siempre apunta a este ALB.
      dns_records = {
        (var.regional_record_name) = {
          zone_name    = var.public_domain_name
          private_zone = false
        }
      }
    }
  }
}

/*----------------------------------------------------------------------*/
/* ECS | Clúster y servicio Keycloak                                    */
/*----------------------------------------------------------------------*/

module "ecs" {
  source  = "gocloudLa/wrapper-ecs/aws"
  version = "1.0.3"

  metadata = local.metadata

  ecs_parameters = {
    (local.ecs_cluster_key) = {
      cluster_capacity_providers = ["FARGATE"]
      default_capacity_provider_strategy = {
        FARGATE = { weight = 100 }
      }
    }
  }
}

# El ALB llega por referencia (local.alb_name deriva del ARN del listener) y la VPC y las
# subredes llegan como valores que dependen de la red creada. Lo único que no se puede
# expresar así es el clúster ECS: ver el depends_on al final del bloque.
module "ecs_service" {
  source  = "gocloudLa/wrapper-ecs-service/aws"
  version = "1.5.0"

  metadata = local.metadata

  ecs_service_parameters = {
    (local.ecs_service_key) = {
      ecs_cluster_name = local.ecs_cluster_name
      vpc_name         = var.vpc_name
      subnet_name      = var.app_subnet_name

      # Las tareas viven en subredes privadas y salen por NAT: no reciben IP pública.
      assign_public_ip       = false
      launch_type            = "FARGATE"
      desired_count          = var.ecs_desired_count
      enable_autoscaling     = false
      enable_execute_command = true
      cpu                    = 1024
      memory                 = 2048

      # Keycloak tarda en arrancar y valida el esquema contra Aurora: sin esta gracia el
      # circuit breaker corta el despliegue antes del primer health check bueno.
      health_check_grace_period_seconds  = 240
      deployment_minimum_healthy_percent = 0
      deployment_maximum_percent         = 100
      deployment_circuit_breaker = {
        enable   = true
        rollback = true
      }

      containers = {
        (local.ecs_container_key) = {
          image                                  = local.keycloak_image
          cloudwatch_log_group_retention_in_days = 14

          map_environment = {
            AWS_REGION = var.aws_region

            # Endpoint del clúster Aurora local a esta región (no el Global Writer
            # Endpoint compartido): cada Keycloak conecta siempre a su propio clúster, así
            # ninguna carga necesita alcanzar la otra región por PostgreSQL. Cuando ARC
            # promueve este clúster, el mismo hostname empieza a aceptar escrituras sin
            # que Keycloak deba reconectar a otro DB_HOST.
            DB_HOST = data.aws_rds_cluster.this.endpoint
            DB_PORT = "5432"
            DB_NAME = var.database_name

            KC_DB              = "postgres"
            KC_HOSTNAME        = "https://${var.app_hostname}"
            KC_PROXY_HEADERS   = "xforwarded"
            KC_HTTP_ENABLED    = "true"
            KC_HEALTH_ENABLED  = "true"
            KC_METRICS_ENABLED = "true"
            KC_CACHE           = "local"

            # Conexiones de vida corta y caché DNS acotada favorecen la reconexión al
            # nuevo writer; no cancelan transacciones en curso ni garantizan RTO.
            KC_DB_POOL_MAX_LIFETIME = "30s"
            JAVA_OPTS_APPEND        = "-Dsun.net.inetaddr.ttl=5"
          }

          # El wrapper crea un parámetro SSM cifrado por cada clave y lo inyecta como
          # secreto de la task definition; los valores no quedan en logs ni en tfvars.
          map_secrets = {
            KC_DB_USERNAME              = var.database_admin_username
            KC_DB_PASSWORD              = var.database_password
            KC_BOOTSTRAP_ADMIN_USERNAME = var.keycloak_bootstrap_admin_username
            KC_BOOTSTRAP_ADMIN_PASSWORD = var.keycloak_bootstrap_admin_password
          }

          ports = {
            http = {
              container_port = 8080

              load_balancer = {
                (var.region_key) = {
                  alb_name                 = local.alb_name
                  alb_listener_port        = 443
                  target_group_custom_name = local.target_group_name
                  deregistration_delay     = 30

                  # El health check apunta al puerto de management de Keycloak, no al
                  # de tráfico: /health/ready sólo existe en 9000.
                  health_check = {
                    path                = "/health/ready"
                    port                = "9000"
                    matcher             = "200-299"
                    interval            = 15
                    timeout             = 5
                    healthy_threshold   = 2
                    unhealthy_threshold = 3
                  }

                  listener_rules = {
                    app = {
                      priority = 100
                      conditions = [{
                        host_headers = [var.app_hostname, var.regional_hostname]
                      }]
                    }
                  }
                }
              }
            }

            management = {
              container_port = 9000
            }
          }
        }
      }
    }
  }

  # Único depends_on que queda. wrapper-ecs no publica ningún output, así que no hay
  # atributo del clúster al que referirse; el ALB ya no lo necesita porque alb_name se
  # deriva del ARN del listener (ver locals.tf). Es el caso que la documentación de
  # Terraform reserva para depends_on: dependencia real sin dato que referenciar.
  depends_on = [module.ecs]
}
