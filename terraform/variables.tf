variable "aws_region" {
  description = "Region to deploy into. Assessment brief allows us-east-1 or eu-west-1."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "eu-west-1"], var.aws_region)
    error_message = "The brief restricts deployment to us-east-1 or eu-west-1."
  }
}

variable "project_name" {
  description = <<-EOT
    Prefix for every resource name, so a teardown is easy to verify. Names what
    the stack runs rather than repeating the repository name, which would
    produce identifiers like `devops-assessment-assessment`.
  EOT
  type        = string
  default     = "hero-api"
}

variable "environment" {
  description = "Environment label; surfaces in tags and in trace attributes."
  type        = string
  default     = "assessment"
}

variable "vpc_cidr" {
  description = "Address space for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = <<-EOT
    Number of availability zones. Two is the minimum an ALB will accept, and the
    minimum at which losing one AZ is survivable.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "An ALB requires at least two AZs; three is the practical ceiling here."
  }
}

variable "container_port" {
  description = "Port the FastAPI container listens on (matches the Dockerfile)."
  type        = number
  default     = 8000
}

variable "image_tag" {
  description = <<-EOT
    Image tag to deploy. The pipeline passes the commit SHA so that every
    deployment is traceable to exactly one commit; `latest` is never used,
    because it makes rollbacks ambiguous.
  EOT
  type        = string
  default     = "bootstrap"
}

variable "desired_count" {
  description = "Number of application tasks. Two so a rolling deploy never drops to zero."
  type        = number
  default     = 2
}

variable "task_cpu" {
  description = "Fargate CPU units (1024 = 1 vCPU)."
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Fargate memory in MiB. Must be a legal pairing with task_cpu."
  type        = number
  default     = 1024
}

variable "db_instance_class" {
  description = "RDS instance class. t4g.micro is Free Tier eligible for 12 months."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL major version for RDS."
  type        = string
  default     = "17"
}

variable "log_retention_days" {
  description = <<-EOT
    CloudWatch Logs retention. Never leave this unset: the default is `Never
    expire`, which quietly bills forever for logs nobody reads.
  EOT
  type        = number
  default     = 7
}

variable "github_repository" {
  description = "owner/repo allowed to assume the deployment role via OIDC."
  type        = string
  default     = "goldkinen/devops-assessment"
}

variable "enable_github_oidc" {
  description = <<-EOT
    Create the GitHub OIDC provider. Set to false if the account already has one
    — the provider is account-global and a second copy will fail to create.
  EOT
  type        = bool
  default     = true
}
