resource "aws_sqs_queue" "send_user_status" {
  name = "${local.resource_name_prefix}-sqs-send-user-status"
}

resource "aws_sfn_state_machine" "send_user_status" {
  name     = "${local.resource_name_prefix}-sfn-send-user-status"
  role_arn = aws_iam_role.sfn_send_user_status.arn

  definition = templatefile("${path.module}/send_user_status.sfn.json", {
    dynamodb_table_creators_name   = data.aws_dynamodb_table.creators.name,
    dynamodb_table_users_name      = data.aws_dynamodb_table.users.name,
    lambda_check_user_auth_arn     = data.aws_lambda_function.check_user_auth.arn,
    lambda_get_user_subs_arn       = data.aws_lambda_function.get_user_subs.arn,
    lambda_send_user_auth_link_arn = aws_lambda_function.send_user_auth_link.arn,
    lambda_send_user_invites_arn   = aws_lambda_function.send_user_invites.arn,
  })

  ### Expected input
  # {
  #   "user_id": "18121313",
  #   "message_id": "460",       (Optional)
  #   "twitch_id": "101319792",
  #   "access_token": "fhasfjakdhflkjdbrhj3r1" (Optional) 
  # }
}

resource "aws_iam_role" "sfn_send_user_status" {
  name               = "${local.resource_name_prefix}-sfn-send-user-status-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role_policy.json
}

data "aws_iam_policy_document" "sfn_send_user_status" {
  statement {
    actions   = ["dynamodb:Scan"]
    resources = [data.aws_dynamodb_table.creators.arn]
    effect    = "Allow"
  }

  statement {
    actions   = ["dynamodb:GetItem"]
    resources = [data.aws_dynamodb_table.users.arn]
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
      data.aws_lambda_function.get_user_subs.arn,
      aws_lambda_function.send_user_auth_link.arn,
      aws_lambda_function.send_user_invites.arn
    ]
    effect = "Allow"
  }
}

resource "aws_iam_role_policy" "sfn_send_user_status" {
  name   = "${local.resource_name_prefix}-sfn-send-user-status-role-policy"
  role   = aws_iam_role.sfn_send_user_status.id
  policy = data.aws_iam_policy_document.sfn_send_user_status.json
}

resource "aws_pipes_pipe" "send_user_status_pipe" {
  name     = "${local.resource_name_prefix}-pipe-send-user-status"
  role_arn = aws_iam_role.eventbridge_pipe_send_user_status.arn

  source = aws_sqs_queue.send_user_status.arn
  source_parameters {
    sqs_queue_parameters {
      batch_size                         = 10
      maximum_batching_window_in_seconds = 0
    }
  }

  target = aws_sfn_state_machine.send_user_status.arn
  target_parameters {
    step_function_state_machine_parameters {
      invocation_type = "FIRE_AND_FORGET"
    }
  }
}

resource "aws_iam_role" "eventbridge_pipe_send_user_status" {
  name               = "${local.resource_name_prefix}-eventbridge-pipe-send-user-status-role"
  assume_role_policy = data.aws_iam_policy_document.pipes_assume_role_policy.json
}

data "aws_iam_policy_document" "eventbridge_pipe_send_user_status" {
  statement {
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.send_user_status.arn]
    effect    = "Allow"
  }

  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [aws_sqs_queue.send_user_status.arn]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "eventbridge_pipe_send_user_status" {
  name   = "${local.resource_name_prefix}-eventbridge-pipe-send-user-status-role-policy"
  role   = aws_iam_role.eventbridge_pipe_send_user_status.id
  policy = data.aws_iam_policy_document.eventbridge_pipe_send_user_status.json
}