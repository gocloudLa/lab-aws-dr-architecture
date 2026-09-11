# Sin wrapper en la Standard Platform: ni el plan de ARC Region switch ni su rol de
# ejecución tienen módulo equivalente, así que se declaran como recursos.

resource "aws_iam_role" "arc" {
  provider = aws.primary

  name = "${local.common_name}-arc-region-switch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "arc-region-switch.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "arc" {
  provider = aws.primary

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
          aws_rds_global_cluster.this.arn,
          module.primary.aurora_cluster_arn,
          module.secondary.aurora_cluster_arn
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
      # política; se acota al tipo de recurso y la zona a la zona pública de la demo.
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
        Resource = "arn:${data.aws_partition.current.partition}:route53:::hostedzone/${var.public_zone_id}"
      },
      # Escalar el ECS de la región destino de 0 a N tareas, acotado a los dos servicios y
      # clústeres de esta demo. Política tomada de la muestra oficial del execution block
      # ECS service scaling (docs.aws.amazon.com/r53recovery/.../security_iam_region_switch_ecs.html).
      {
        Sid    = "EscalarSoloLosServiciosDeEstaDemo"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService"
        ]
        Resource = [
          module.primary.ecs_service_arn,
          module.secondary.ecs_service_arn
        ]
      },
      {
        Sid    = "DescribirClustersDeEstaDemo"
        Effect = "Allow"
        Action = ["ecs:DescribeClusters"]
        Resource = [
          module.primary.ecs_cluster_arn,
          module.secondary.ecs_cluster_arn
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

# El plan tiene exactamente tres pasos, en orden estricto: primero Aurora cambia de
# writer, después el ECS de la región destino escala de 0 a N tareas (pilot light: recién
# ahí Keycloak arranca y corre sus migraciones de escritura, con el clúster local ya
# promovido) y por último DNS publica el ALB de la región destino. No hay gate posterior
# a la promoción de Aurora más allá de esperar a que el ECS quede con capacidad.
resource "aws_arcregionswitch_plan" "this" {
  provider = aws.primary

  name                            = "${local.common_name}-recovery"
  description                     = "Promueve Aurora Global Database y despues conmuta el DNS publico de la aplicacion"
  execution_role                  = aws_iam_role.arc.arn
  primary_region                  = var.primary_region
  recovery_approach               = "activePassive"
  recovery_time_objective_minutes = var.arc_recovery_time_objective_minutes
  regions                         = [var.primary_region, var.secondary_region]

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
          database_cluster_arns     = [module.primary.aurora_cluster_arn, module.secondary.aurora_cluster_arn]
          global_cluster_identifier = aws_rds_global_cluster.this.id
          timeout_minutes           = 20
          ungraceful { ungraceful = "failover" }
        }
      }

      # Pilot light: escala el ECS de la región que este workflow activa, de 0 a N tareas,
      # sólo después de que su clúster Aurora ya es writer. capacity_monitoring_approach
      # usa el desired count real del servicio origen (sin costo adicional de Container
      # Insights); target_percent=100 pide igualar esa capacidad en el destino.
      step {
        name                 = "scale-up-keycloak"
        execution_block_type = "ECSServiceScaling"

        ecs_capacity_increase_config {
          capacity_monitoring_approach = "sampledMaxInLast24Hours"
          target_percent               = 100
          timeout_minutes              = 10

          service {
            cluster_arn = module.primary.ecs_cluster_arn
            service_arn = module.primary.ecs_service_arn
          }

          service {
            cluster_arn = module.secondary.ecs_cluster_arn
            service_arn = module.secondary.ecs_service_arn
          }

          ungraceful { minimum_success_percentage = 0 }
        }
      }

      step {
        name                 = "switch-public-application-dns"
        execution_block_type = "Route53HealthCheck"

        route53_health_check_config {
          hosted_zone_id  = var.public_zone_id
          record_name     = local.app_record_name
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
