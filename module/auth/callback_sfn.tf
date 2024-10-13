resource "aws_sfn_state_machine" "twitch_callback" {
  name     = "${local.resource_name_prefix}-sfn-twitch-callback"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = templatefile("${path.module}/callback.sfn.json", {
    dynamodb_table_auth_states_name = data.aws_dynamodb_table.auth_states.name,
    lambda_twitch_callback_arn      = aws_lambda_function.twitch_callback.arn
  })
}

data "aws_iam_policy_document" "sfn_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "step_functions_role" {
  name               = "${local.resource_name_prefix}-sfn-twitch-callback-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role_policy.json
}

data "aws_iam_policy_document" "sfn_twitch_callback" {
  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:DeleteItem"]
    resources = [data.aws_dynamodb_table.auth_states.arn]
    effect    = "Allow"
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
    effect    = "Allow"
  }

  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.twitch_callback.arn]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "sfn_twitch_callback" {
  name   = "${local.resource_name_prefix}-sfn-twitch-callback-role-policy"
  role   = aws_iam_role.step_functions_role.id
  policy = data.aws_iam_policy_document.sfn_twitch_callback.json
}
