/*----------------------------------------------------------------------*/
/* KMS | Cifrado en reposo de los clústeres Aurora, una clave por región */
/*----------------------------------------------------------------------*/

# Un Global Database cifrado exige una clave KMS explícita y válida en la región de cada
# clúster: sin kms_key_id, AWS intenta reusar la clave del clúster de origen (us-east-2) al
# crear el secundario y falla con "InvalidParameterCombination: For encrypted cross-region
# replica, kmsKeyId should be explicitly specified".
#
# Las claves se crean en esta capa (la más baja del stack, cross-region por naturaleza) para
# que su ARN llegue a las capas regionales como un output concreto. Si se crearan en la misma
# capa que Aurora, el ARN sería un valor unknown en plan, se propagaría por los merge/flatten
# internos del wrapper y rompería un count interno; exactamente la condición de carrera que
# la separación en capas de Terragrunt busca eliminar.
#
# Se usa una clave administrada por el cliente (CMK) en vez de la gestionada aws/rds porque la
# política de aws/rds no se puede editar ni compartir: con una CMK propia el lab puede auditar
# el uso en CloudTrail y restaurar snapshots en otra cuenta.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Misma política para ambas claves: delega la administración en IAM (no en la sesión efímera
# de SSO que aplica) y habilita a RDS a cifrar/descifrar el almacenamiento del clúster.
data "aws_iam_policy_document" "aurora_kms" {
  #checkov:skip=CKV_AWS_109:Política de recurso de una KMS key, no política de identidad: "*" en resources es el patrón estándar de AWS y se refiere implícitamente a esta clave, no a la cuenta.
  #checkov:skip=CKV_AWS_356:Ídem — resource-based policy de KMS; "*" es obligatorio en este tipo de política y no habilita acceso fuera de esta clave.
  #checkov:skip=CKV_AWS_111:Ídem — el acceso de escritura ya está acotado a esta clave por ser su propia resource policy, y el principal de EnableIAMUserPermissions es sólo el root de esta cuenta.
  statement {
    sid       = "EnableIAMUserPermissions"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid = "AllowRDSUseOfTheKey"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    principals {
      type = "Service"
      identifiers = [
        "rds.amazonaws.com",
        "monitoring.rds.amazonaws.com",
      ]
    }
  }
}

# Clave de la región primaria (Ohio) — provider por defecto.
resource "aws_kms_key" "primary" {
  description             = "Cifrado en reposo del cluster Aurora ${local.kms_key_name[local.metadata.key.region]}"
  policy                  = data.aws_iam_policy_document.aurora_kms.json
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = merge(local.metadata.common_tags, {
    Name = local.kms_key_name[local.metadata.key.region]
  })
}

resource "aws_kms_alias" "primary" {
  name          = "alias/${local.kms_key_name[local.metadata.key.region]}"
  target_key_id = aws_kms_key.primary.key_id
}

# Clave de la región secundaria (Virginia) — provider aliased. Las claves KMS son regionales,
# por eso el secundario necesita su propia clave creada con el provider de us-east-1.
resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Cifrado en reposo del cluster Aurora ${local.kms_key_name["secondary"]}"
  policy                  = data.aws_iam_policy_document.aurora_kms.json
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = merge(local.metadata.common_tags, {
    Name = local.kms_key_name["secondary"]
  })
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${local.kms_key_name["secondary"]}"
  target_key_id = aws_kms_key.secondary.key_id
}
