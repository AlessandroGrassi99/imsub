resource "aws_sqs_queue" "check_join_request" {
  name = "${local.resource_name_prefix}-sqs-check-join-request"
}

resource "aws_sfn_state_machine" "check_join_request" {
  name     = "${local.resource_name_prefix}-sfn-check-join-request"
  role_arn = aws_iam_role.sfn_check_join_request.arn

  definition = templatefile("${path.module}/check_join_request.sfn.json", {
    dynamodb_table_creators_name        = data.aws_dynamodb_table.creators.name,
    dynamodb_table_users_name           = data.aws_dynamodb_table.users.name,
    lambda_check_user_auth_arn          = data.aws_lambda_function.check_user_auth.arn,
    lambda_get_user_subs_arn            = data.aws_lambda_function.get_user_subs.arn,
    lambda_send_join_request_choice_arn = aws_lambda_function.send_join_request_choice.arn
  })

  ### Expected input
  # {
  #   "user_id": "18121313",
  #   "message_id": "460",       (Optional)
  #   "twitch_id": "101319792",
  #   "access_token": "fhasfjakdhflkjdbrhj3r1" (Optional) 
  # }
}

resource "aws_iam_role" "sfn_check_join_request" {
  name               = "${local.resource_name_prefix}-sfn-check-join-request-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role_policy.json
}

data "aws_iam_policy_document" "sfn_check_join_request" {
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
      aws_lambda_function.send_user_invites.arn,
      aws_lambda_function.send_join_request_choice.arn
    ]
    effect = "Allow"
  }
}

resource "aws_iam_role_policy" "sfn_check_join_request" {
  name   = "${local.resource_name_prefix}-sfn-check-join-request-role-policy"
  role   = aws_iam_role.sfn_check_join_request.id
  policy = data.aws_iam_policy_document.sfn_check_join_request.json
}

resource "aws_pipes_pipe" "check_join_request_pipe" {
  name     = "${local.resource_name_prefix}-pipe-check-join-request"
  role_arn = aws_iam_role.eventbridge_pipe_check_join_request.arn

  source = aws_sqs_queue.check_join_request.arn
  source_parameters {
    sqs_queue_parameters {
      batch_size                         = 10
      maximum_batching_window_in_seconds = 0
    }
  }

  target = aws_sfn_state_machine.check_join_request.arn
  target_parameters {
    step_function_state_machine_parameters {
      invocation_type = "FIRE_AND_FORGET"
    }
  }
}

resource "aws_iam_role" "eventbridge_pipe_check_join_request" {
  name               = "${local.resource_name_prefix}-eventbridge-pipe-check-join-request-role"
  assume_role_policy = data.aws_iam_policy_document.pipes_assume_role_policy.json
}

data "aws_iam_policy_document" "eventbridge_pipe_check_join_request" {
  statement {
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.check_join_request.arn]
    effect    = "Allow"
  }

  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [aws_sqs_queue.check_join_request.arn]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "eventbridge_pipe_check_join_request" {
  name   = "${local.resource_name_prefix}-eventbridge-pipe-check-join-request-role-policy"
  role   = aws_iam_role.eventbridge_pipe_check_join_request.id
  policy = data.aws_iam_policy_document.eventbridge_pipe_check_join_request.json
}