data "aws_partition" "current" {}

data "aws_route53_zone" "public" {
  name         = var.zone_public
  private_zone = false
}

/*----------------------------------------------------------------------*/
/* IAM | Rol de ejecución de ARC Region switch                          */
/*----------------------------------------------------------------------*/

# Sin wrapper en la Standard Platform: ni el plan de ARC ni su rol de ejecución tienen
# módulo equivalente, así que se declaran como recursos.
resource "aws_iam_role" "arc" {
  name = "${local.common_name}-arc-region-switch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "arc-region-switch.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.metadata.common_tags
}

resource "aws_iam_role_policy" "arc" {
  #checkov:skip=CKV_AWS_355:Los statements con Resource="*" son para acciones que no admiten scoping por recurso (Describe*/List* de RDS y ECS, application-autoscaling, cloudwatch:GetMetricStatistics); las acciones que sí lo admiten (Failover/SwitchoverGlobalCluster, UpdateService) ya están acotadas a los ARN de esta demo.
  #checkov:skip=CKV_AWS_290:Ídem — el "*" está limitado a acciones de sólo lectura o a APIs sin soporte de resource-level permissions; ninguna acción de escritura del rol usa "*".
  name = "region-switch-execution"
  role = aws_iam_role.arc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Las acciones que mutan estado se acotan al Global Database de esta demo y a sus dos
      # clústeres regionales: el rol no puede promover ninguna otra base de la cuenta.
      {
        Sid    = "PromoverSoloEsteGlobalDatabase"
        Effect = "Allow"
        Action = [
          "rds:FailoverGlobalCluster",
          "rds:SwitchoverGlobalCluster"
        ]
        Resource = [
          var.global_cluster_arn,
          var.primary_aurora_cluster_arn,
          var.secondary_aurora_cluster_arn
        ]
      },
      # Las Describe de RDS no admiten permisos por recurso: la API las evalúa contra "*".
      {
        Sid    = "DescribirEstadoDeAurora"
        Effect = "Allow"
        Action = [
          "rds:DescribeGlobalClusters",
          "rds:DescribeDBClusters"
        ]
        Resource = "*"
      },
      # Los health checks los crea ARC, así que sus IDs no se conocen al escribir la
      # política; se acota al tipo de recurso, y la zona a la zona pública de la demo.
      {
        Sid    = "ConmutarHealthChecksDeLaZona"
        Effect = "Allow"
        Action = [
          "route53:GetHealthCheck",
          "route53:GetHealthCheckStatus",
          "route53:UpdateHealthCheck"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:route53:::healthcheck/*"
      },
      {
        Sid      = "LeerRegistrosDeLaZonaPublica"
        Effect   = "Allow"
        Action   = ["route53:ListResourceRecordSets"]
        Resource = "arn:${data.aws_partition.current.partition}:route53:::hostedzone/${data.aws_route53_zone.public.zone_id}"
      },
      # Escalar el ECS de la región destino de 0 a N tareas, acotado a los dos servicios y
      # clústeres de esta demo. Política tomada de la muestra oficial del execution block
      # de ECS service scaling.
      {
        Sid    = "EscalarSoloLosServiciosDeEstaDemo"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService"
        ]
        Resource = [
          var.primary_ecs_service_arn,
          var.secondary_ecs_service_arn
        ]
      },
      {
        Sid    = "DescribirClustersDeEstaDemo"
        Effect = "Allow"
        Action = ["ecs:DescribeClusters"]
        Resource = [
          var.primary_ecs_cluster_arn,
          var.secondary_ecs_cluster_arn
        ]
      },
      # ecs:ListServices y las de Application Auto Scaling no admiten scoping por recurso.
      {
        Sid      = "ListarServiciosEcs"
        Effect   = "Allow"
        Action   = ["ecs:ListServices"]
        Resource = "*"
      },
      {
        Sid    = "LeerCapacidadDeAutoscaling"
        Effect = "Allow"
        Action = [
          "application-autoscaling:DescribeScalableTargets",
          "application-autoscaling:RegisterScalableTarget"
        ]
        Resource = "*"
      },
      {
        Sid      = "LeerMetricaDeTareasCorriendo"
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricStatistics"]
        Resource = "*"
      }
    ]
  })
}

/*----------------------------------------------------------------------*/
/* ARC Region switch | Plan de conmutación                              */
/*----------------------------------------------------------------------*/

# Tres pasos, en orden estricto: Aurora cambia de writer, después ARC reafirma la capacidad
# del ECS de la región destino (warm standby: ya estaba programada, pero recién ahora su Aurora
# permite escrituras) y por último DNS publica el ALB destino.
resource "aws_arcregionswitch_plan" "this" {
  name                            = "${local.common_name}-recovery"
  description                     = "Promueve Aurora Global Database, escala el ECS destino y despues conmuta el DNS publico"
  execution_role                  = aws_iam_role.arc.arn
  primary_region                  = var.primary_region
  recovery_approach               = "activePassive"
  recovery_time_objective_minutes = var.arc_recovery_time_objective_minutes
  regions                         = [var.primary_region, var.secondary_region]

  tags = local.metadata.common_tags

  dynamic "workflow" {
    for_each = toset([var.primary_region, var.secondary_region])

    content {
      workflow_description   = "Activa ${workflow.value} con ${var.arc_aurora_behavior}"
      workflow_target_action = "activate"
      workflow_target_region = workflow.value

      step {
        name                 = "promote-aurora"
        execution_block_type = "AuroraGlobalDatabase"

        global_aurora_config {
          behavior                  = var.arc_aurora_behavior
          database_cluster_arns     = [var.primary_aurora_cluster_arn, var.secondary_aurora_cluster_arn]
          global_cluster_identifier = var.global_cluster_identifier
          timeout_minutes           = 20
          ungraceful { ungraceful = "failover" }
        }
      }

      # Gate real: ARC espera a que el ECS destino alcance la capacidad pedida (o el
      # timeout) antes de pasar al paso de DNS, así Route 53 no publica un ALB sin backend.
      # capacity_monitoring_approach usa el desired count real del servicio origen, sin
      # costo adicional de Container Insights.
      step {
        name                 = "scale-up-keycloak"
        execution_block_type = "ECSServiceScaling"

        ecs_capacity_increase_config {
          capacity_monitoring_approach = "sampledMaxInLast24Hours"
          target_percent               = 100
          timeout_minutes              = 10

          service {
            cluster_arn = var.primary_ecs_cluster_arn
            service_arn = var.primary_ecs_service_arn
          }

          service {
            cluster_arn = var.secondary_ecs_cluster_arn
            service_arn = var.secondary_ecs_service_arn
          }

          ungraceful { minimum_success_percentage = 0 }
        }
      }

      step {
        name                 = "switch-public-application-dns"
        execution_block_type = "Route53HealthCheck"

        route53_health_check_config {
          hosted_zone_id  = data.aws_route53_zone.public.zone_id
          record_name     = var.app_hostname
          timeout_minutes = 5

          dynamic "record_set" {
            for_each = toset([var.primary_region, var.secondary_region])

            content {
              record_set_identifier = record_set.value
              region                = record_set.value
            }
          }
        }
      }
    }
  }
}

/*----------------------------------------------------------------------*/
/* DNS | Registros FAILOVER asociados a los health checks de ARC        */
/*----------------------------------------------------------------------*/

data "aws_arcregionswitch_route53_health_checks" "traffic" {
  plan_arn = aws_arcregionswitch_plan.this.arn
}

locals {
  app_health_check_matches = {
    for region in [var.primary_region, var.secondary_region] : region => [
      for check in data.aws_arcregionswitch_route53_health_checks.traffic.health_checks : check.health_check_id
      if check.region == region && check.hosted_zone_id == data.aws_route53_zone.public.zone_id && trimsuffix(check.record_name, ".") == var.app_hostname
    ]
  }

  app_health_checks = {
    for region, matches in local.app_health_check_matches : region => try(matches[0], null)
  }
}

# evaluate_target_health queda en false a propósito: sólo ARC decide la conmutación, así el
# orden promoción-de-Aurora, escalado de ECS y DNS no lo puede alterar Route 53 por su cuenta.
resource "aws_route53_record" "application_primary" {
  zone_id         = data.aws_route53_zone.public.zone_id
  name            = var.app_hostname
  type            = "A"
  set_identifier  = var.primary_region
  health_check_id = local.app_health_checks[var.primary_region]

  failover_routing_policy { type = "PRIMARY" }

  alias {
    name                   = var.primary_alb_dns_name
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = false
  }

  lifecycle {
    precondition {
      condition     = length(local.app_health_check_matches[var.primary_region]) == 1
      error_message = "ARC debe exponer exactamente un health check para ${var.app_hostname} en ${var.primary_region}."
    }
  }
}

resource "aws_route53_record" "application_secondary" {
  zone_id         = data.aws_route53_zone.public.zone_id
  name            = var.app_hostname
  type            = "A"
  set_identifier  = var.secondary_region
  health_check_id = local.app_health_checks[var.secondary_region]

  failover_routing_policy { type = "SECONDARY" }

  alias {
    name                   = var.secondary_alb_dns_name
    zone_id                = var.secondary_alb_zone_id
    evaluate_target_health = false
  }

  lifecycle {
    precondition {
      condition     = length(local.app_health_check_matches[var.secondary_region]) == 1
      error_message = "ARC debe exponer exactamente un health check para ${var.app_hostname} en ${var.secondary_region}."
    }
  }
}
