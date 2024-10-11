resource "aws_api_gateway_account" "common" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_account.arn
}

data "aws_iam_policy_document" "api_gateway_account_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "api_gateway_account" {
  name               = "${local.resource_name_prefix}-api-gateway-role"
  assume_role_policy = data.aws_iam_policy_document.api_gateway_account_assume_role.json
}

data "aws_iam_policy_document" "api_gateway_account" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
      "logs:GetLogEvents",
      "logs:FilterLogEvents",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "api_gateway_account" {
  name   = "${local.resource_name_prefix}-api-gateway-role-policy"
  role   = aws_iam_role.api_gateway_account.id
  policy = data.aws_iam_policy_document.api_gateway_account.json
}