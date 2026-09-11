data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

/*----------------------------------------------------------------------*/
/* ECS Service | Keycloak                                               */
/*----------------------------------------------------------------------*/

# Capa propia porque necesita el ALB (listener 443), el ECR y el endpoint de Aurora ya
# creados. Con todo eso resuelto por la capa project, el for_each de los target groups y
# de la task definition se expande sin valores unknown.
module "ecs_service" {
  source  = "gocloudLa/wrapper-ecs-service/aws"
  version = "1.5.0"

  metadata = local.metadata

  ecs_service_parameters = {
    (local.ecs_service_key) = {
      ecs_cluster_name = var.ecs_cluster_name
      vpc_name         = var.vpc_name
      subnet_name      = var.app_subnet_name

      # Las tareas viven en subredes privadas y salen por NAT: no reciben IP pública.
      assign_public_ip = false
      launch_type      = "FARGATE"

      # El módulo base de ECS mantiene desired_count en ignore_changes (asume que la escala
      # se gobierna por autoscaling), así que un desired_count por Terraform no se aplica tras
      # la creación. Por eso la escala se maneja con un scalable target de Application Auto
      # Scaling: min=max fija el número de tareas y es lo que ARC ajusta en el switchover.
      # desired_count sólo siembra el valor inicial del target (min = min(min_capacity,
      # desired_count)); tiene que ser >= autoscaling_min_capacity o el piso caería a 0.
      desired_count            = var.ecs_desired_count
      enable_autoscaling       = true
      autoscaling_min_capacity = var.ecs_desired_count
      autoscaling_max_capacity = var.ecs_desired_count
      enable_execute_command   = true
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

            # Endpoint del clúster Aurora local a esta región. Mientras la región es
            # secundaria ese endpoint es de sólo lectura, así que la tarea de Keycloak falla
            # en bucle (warm standby); cuando ARC promueve el clúster, el mismo hostname
            # acepta escrituras y el container arranca sano sin reconectar a otro DB_HOST.
            DB_HOST = var.db_host
            DB_PORT = "5432"
            DB_NAME = var.database_name

            KC_DB              = "postgres"
            KC_HOSTNAME        = "https://${var.app_hostname}"
            KC_PROXY_HEADERS   = "xforwarded"
            KC_HTTP_ENABLED    = "true"
            KC_HEALTH_ENABLED  = "true"
            KC_METRICS_ENABLED = "true"
            KC_CACHE           = "local"

            # Conexiones de vida corta y caché DNS acotada favorecen la reconexión después
            # de una promoción; no cancelan transacciones ni garantizan RTO.
            KC_DB_POOL_MAX_LIFETIME = "30s"
            JAVA_OPTS_APPEND        = "-Dsun.net.inetaddr.ttl=5"
          }

          # El wrapper crea un parámetro SSM cifrado por cada clave y lo inyecta como
          # secreto de la task definition; los valores no quedan en logs ni en el state
          # en claro.
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
                  alb_name                 = var.alb_name
                  alb_listener_port        = 443
                  target_group_custom_name = local.target_group_name
                  deregistration_delay     = 30

                  # El health check apunta al puerto de management de Keycloak, no al de
                  # tráfico: /health/ready sólo existe en 9000.
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
}
