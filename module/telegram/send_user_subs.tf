resource "aws_sqs_queue" "send_user_subs" {
  name = "${local.resource_name_prefix}-sqs-send-user-subs"
}

resource "aws_sfn_state_machine" "send_user_subs" {
  name     = "${local.resource_name_prefix}-sfn-send-user-subs"
  role_arn = aws_iam_role.sfn_send_user_subs.arn

  definition = templatefile("${path.module}/send_user_subs.sfn.json", {
    # lambda_check_user_auth_arn    = data.aws_lambda_function.check_user_auth.arn,
    dyanamodb_table_creators_name = data.aws_dynamodb_table.creators.name,
    lambda_get_user_subs_arn      = data.aws_lambda_function.get_user_subs.arn
  })

  ### Expected input
  # {
  #   "user_id": "18121313",
  #   "message_id": "460",       (Optional)
  #   "twitch_id": "101319792",
  #   "access_token": "fhasfjakdhflkjdbrhj3r1" (Optional) 
  # }
}

resource "aws_iam_role" "sfn_send_user_subs" {
  name               = "${local.resource_name_prefix}-sfn-send-user-subs-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role_policy.json
}

data "aws_iam_policy_document" "sfn_send_user_subs" {
  statement {
    actions   = ["dynamodb:Scan"]
    resources = [data.aws_dynamodb_table.creators.arn]
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
    actions = ["lambda:InvokeFunction"]
    resources = [
      data.aws_lambda_function.check_user_auth.arn,
      data.aws_lambda_function.get_user_subs.arn
    ]
    effect = "Allow"
  }
}

resource "aws_iam_role_policy" "sfn_send_user_subs" {
  name   = "${local.resource_name_prefix}-sfn-send-user-subs-role-policy"
  role   = aws_iam_role.sfn_send_user_subs.id
  policy = data.aws_iam_policy_document.sfn_send_user_subs.json
}
