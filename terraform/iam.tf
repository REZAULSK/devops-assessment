# ---------------------------------------------------------------------------
# Task roles
#
# ECS uses two roles per task and they are not interchangeable:
#
#   execution role - used by the ECS agent, before the container starts, to pull
#                    the image, fetch secrets, and create log streams.
#   task role      - assumed by the application code itself, at runtime.
#
# Keeping them apart means the running container cannot read the secret it was
# started with, and cannot pull other images.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ----------------------------- execution ------------------------------------

resource "aws_iam_role" "task_execution" {
  name               = "${local.name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Scoped to this one secret. The managed policy above deliberately grants no
# Secrets Manager access, so this is the only path to the connection string.
data "aws_iam_policy_document" "task_execution_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.database_url.arn]
  }
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  name   = "read-database-secret"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_secrets.json
}

# -------------------------------- task --------------------------------------

resource "aws_iam_role" "task" {
  name               = "${local.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

# X-Ray's write APIs take no resource ARN — segments are not addressable objects
# — so `*` here is the narrowest grant the API supports, not a shortcut.
data "aws_iam_policy_document" "task_telemetry" {
  statement {
    sid = "PublishTraces"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
}

resource "aws_iam_role_policy" "task_telemetry" {
  name   = "telemetry"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_telemetry.json
}

# `aws ecs execute-command` needs a channel to SSM. Enabled because the
# alternative when a task misbehaves in a private subnet is redeploying with
# extra logging and waiting.
data "aws_iam_policy_document" "task_exec_command" {
  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_exec_command" {
  name   = "ecs-exec"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_exec_command.json
}
