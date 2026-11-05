# IAM role that GitHub Actions assumes (via OIDC) to deploy to the cluster.
# Least privilege: it can describe the cluster (needed for update-kubeconfig)
# and has edit rights inside ONE Kubernetes namespace. It cannot push images.

variable "github_repo" {
  description = "GitHub repository allowed to deploy, as owner/repo"
  type        = string
}

# The deploy job runs in a GitHub Environment, which changes the OIDC "sub" claim
# to repo:<owner/repo>:environment:<name> (the branch is no longer part of it).
# Restrict branches in GitHub: Settings > Environments > production > Deployment branches.
variable "github_deploy_environment" {
  type    = string
  default = "production"
}

# The GitHub OIDC provider already exists in your account (your ECR-push role uses it)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_trust" {
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

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:environment:${var.github_deploy_environment}"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.project}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

data "aws_iam_policy_document" "github_deploy" {
  statement {
    actions   = ["eks:DescribeCluster"]
    resources = [module.eks.cluster_arn]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "describe-cluster"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}

# Map the IAM role to Kubernetes permissions (EKS access entry)
resource "aws_eks_access_entry" "github_deploy" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_deploy.arn
}

resource "aws_eks_access_policy_association" "github_deploy" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_eks_access_entry.github_deploy.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [var.app_namespace]
  }
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}
