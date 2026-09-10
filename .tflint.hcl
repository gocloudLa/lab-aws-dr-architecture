config {
  # Los módulos externos son responsabilidad de sus repositorios; aquí se analiza
  # el código propio y los módulos locales de esta demo.
  call_module_type = "local"
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
