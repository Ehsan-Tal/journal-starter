# IAM role that the CI *build* job assumes (via OIDC) to push images to ECR.
# Least privilege: it can push to the ONE repository managed in ecr.tf and
# nothing else, and only from the configured branch. It replaces the manually
# created "role-to-permit-github-actions-push-to-ecr" role.
# (Reuses var.github_repo and the OIDC provider data source from github_deploy.tf.)

variable "github_push_branch" {
  description = "Only workflow runs on this branch may push images"
  type        = string
  default     = "main"
}

data "aws_iam_policy_document" "github_push_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The build job has no GitHub Environment, so its sub claim is branch-based.
    # Pull-request runs ("...:pull_request") are therefore NOT allowed to push.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/${var.github_push_branch}"]
    }
  }
}

resource "aws_iam_role" "github_push" {
  name               = "${var.project}-github-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.github_push_trust.json
}

data "aws_iam_policy_document" "github_push" {
  # Login token; this action cannot be scoped to a resource
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push-only access to this repository
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_role_policy" "github_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github_push.id
  policy = data.aws_iam_policy_document.github_push.json
}

output "github_push_role_arn" {
  description = "Store as the AWS_ECR_PUSH_ROLE_ARN GitHub Actions variable"
  value       = aws_iam_role.github_push.arn
}
