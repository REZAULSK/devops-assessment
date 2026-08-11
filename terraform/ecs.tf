resource "aws_ecs_cluster" "main" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "disabled" # Costs per metric; the brief's budget does not stretch to it.
  }
}

# ---------------------------------------------------------------------------
# Task definition
#
# Two containers in one task: the application, and the ADOT collector beside it.
#
# The sidecar shape is chosen over a shared central collector because in awsvpc
# mode both containers share a network namespace, so the application can export
# to 127.0.0.1 and no telemetry ever crosses the network. It also means the
# collector scales with the application automatically and cannot become a single
# point of failure for every service at once.
#
# The cost is one extra container's memory per task. At this size that is the
# cheaper problem.
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "app" {
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "ENVIRONMENT", value = var.environment },
        { name = "LOG_LEVEL", value = "INFO" },
        { name = "DEBUG", value = "false" },
        { name = "OTEL_SERVICE_NAME", value = local.name },
        # Same task, same network namespace: this never leaves the task.
        { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://127.0.0.1:4317" },
      ]

      # Resolved by the ECS agent at task start, using the execution role.
      # The value never appears in the task definition itself.
      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = aws_secretsmanager_secret.database_url.arn
        }
      ]

      # Start order only. ECS has no way to wait for "collector is ready", but
      # the OTLP exporter buffers and retries, so a few seconds of collector
      # startup costs nothing.
      dependsOn = [
        {
          containerName = "aws-otel-collector"
          condition     = "START"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "api"
        }
      }
    },

    {
      name      = "aws-otel-collector"
      image     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
      essential = true

      # Config travels as an environment variable rather than as a baked image
      # or an SSM parameter: it stays reviewable in git, and changing it is a
      # task definition revision like any other change.
      environment = [
        { name = "AOT_CONFIG_CONTENT", value = file("${path.module}/../observability/collector-aws.yaml") },
        { name = "AWS_REGION", value = var.aws_region },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "otel"
        }
      }
    }
  ])
}

# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------

resource "aws_ecs_service" "app" {
  name            = local.name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Lets `aws ecs execute-command` open a shell in a task that is failing in a
  # private subnet, instead of redeploying with more print statements.
  enable_execute_command = true

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false # Egress goes through the NAT gateway.
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "api"
    container_port   = var.container_port
  }

  # The application builds its schema during startup, so first boot is slower
  # than steady state. Without this grace period the ALB can mark a task
  # unhealthy while it is still legitimately starting.
  health_check_grace_period_seconds = 60

  # Rolling update that never drops below the current capacity: 100% minimum
  # healthy with 200% maximum means new tasks come up before old ones go away.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Without this, a broken image deploys, every task crashloops, and the service
  # sits there failing until a human notices. With it, ECS gives up and puts the
  # previous task definition back.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # The pipeline updates the image tag directly on the service, so Terraform
  # must not treat the running revision as drift and roll it back on the next
  # apply. Terraform owns the shape of the service; the pipeline owns which
  # image it runs.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.http]
}
