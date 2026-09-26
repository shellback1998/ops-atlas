# Add as terraform/aws/github-deploy.tf alongside the existing EC2 instance.
# The instance and this deployment role share the same Terraform state.
data "aws_caller_identity" "github_deploy" {}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "ops_atlas_github_deploy" {
  name = "ops-atlas-github-deploy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = [
            "repo:shellback1998/ops-atlas:ref:refs/heads/main",
            "repo:shellback1998@11851758/ops-atlas@1389405984:ref:refs/heads/main"
          ]
        }
      }
    }]
  })
  tags = {
    Project   = "ops-atlas"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy" "ops_atlas_github_ssm" {
  name = "ops-atlas-ssm-deploy"
  role = aws_iam_role.ops_atlas_github_deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RunShellScriptOnOpsAtlasOnly"
        Effect = "Allow"
        Action = ["ssm:SendCommand"]
        Resource = [
          "arn:aws:ssm:us-east-1::document/AWS-RunShellScript",
          aws_instance.ops_atlas.arn
        ]
      },
      {
        Sid      = "ReadRunCommandResult"
        Effect   = "Allow"
        Action   = ["ssm:GetCommandInvocation"]
        Resource = "*"
      }
    ]
  })
}

output "github_deploy_role_arn" {
  value = aws_iam_role.ops_atlas_github_deploy.arn
}
