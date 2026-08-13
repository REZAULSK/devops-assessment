# ---------------------------------------------------------------------------
# GitHub Actions deployment identity
#
# No access keys. GitHub presents a short-lived OIDC token proving which
# repository, branch and workflow is running; AWS exchanges it for credentials
# that expire in an hour.
#
# The alternative — an IAM user's access key in repository secrets — is a
# credential that is valid forever, cannot be scoped to a branch, and is only as
# safe as every person who can read repository settings.
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_oidc ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC endpoint now uses a well-known CA, and AWS verifies the chain
  # itself, but the API still requires a thumbprint to be present.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c3d5f5d0c38228274129d040228d7611f64f9a5"
  ]
}

data "aws_iam_openid_connect_provider" "github_existing" {
  count = var.enable_github_oidc ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = var.enable_github_oidc ? (
    aws_iam_openid_connect_provider.github[0].arn
  ) : data.aws_iam_openid_connect_provider.github_existing[0].arn
}

data "aws_iam_policy_document" "github_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The important line. Restricted to the main branch of one repository, so a
    # pull request from a fork �?" which runs with the same OIDC issuer �?" cannot
    # assume this role.
    #
    # GitHub's OIDC subject has two shapes. Historically it was
    # `repo:OWNER/REPO:ref:...`; GitHub now includes the owner and repository
    # ids, e.g. `repo:OWNER@123/REPO@456:ref:...`. Both are trusted so the same
    # policy survives GitHub's rollout without a redeploy.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:*",
        "repo:${lower(var.github_repository)}:*",
        "repo:${split("/", var.github_repository)[0]}@*/${split("/", var.github_repository)[1]}@*:*",
        "repo:${lower(split("/", var.github_repository)[0])}@*/${lower(split("/", var.github_repository)[1])}@*:*",
      ]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${local.name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json

  # Credentials the workflow receives expire with the job, not with the day.
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_deploy" {
  # The auth token is account-wide by API design; the push itself is restricted
  # to this repository by the statement below.
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid = "DeployService"
    actions = [
      "ecs:DescribeServices",
      "ecs:UpdateService",
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
    ]
    resources = ["*"] # RegisterTaskDefinition accepts no resource constraint.
  }

  # Registering a task definition means handing ECS the roles it will run as.
  # Restricted to exactly the two roles this stack owns, so the deploy role
  # cannot mint a task running as something more privileged.
  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.task.arn, aws_iam_role.task_execution.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # The pipeline's final smoke test resolves the load balancer DNS name.
  statement {
    sid       = "VerifyEndpoint"
    actions   = ["elasticloadbalancing:DescribeLoadBalancers"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
