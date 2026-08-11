terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # State is local by design for this assessment: the stack is created and
  # destroyed by one person on one machine within a couple of days, and a remote
  # backend would itself need bootstrapping (bucket, lock table, and their own
  # lifecycle) that nothing here justifies.
  #
  # Anything longer-lived than this belongs in a shared backend — the moment a
  # second person or a pipeline runs `apply`, local state becomes the outage.
  #
  # backend "s3" {
  #   bucket       = "REPLACE-tfstate"
  #   key          = "devops-assessment/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}
