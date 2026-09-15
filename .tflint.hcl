config {
  # Los módulos externos son responsabilidad de sus repositorios; aquí se analiza
  # el código propio y los módulos locales de esta demo.
  call_module_type = "local"
}

# Terragrunt genera versions.tf (required_version + required_providers) de forma centralizada
# en root.hcl para todas las capas; ese archivo no existe en el árbol estático hasta que corre
# terragrunt, así que TFLint no lo ve y marca cada capa como si le faltara. Declarar el bloque
# también en cada main.tf duplicaría la fuente de verdad y podría chocar con el "generate" de
# Terragrunt (if_exists = "overwrite_terragrunt").
rule "terraform_required_version" {
  enabled = false
}

rule "terraform_required_providers" {
  enabled = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
