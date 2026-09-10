terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 6.0"
      configuration_aliases = [aws.primary, aws.secondary]
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7"
    }
  }
}
