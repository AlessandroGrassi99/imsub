resource "aws_sqs_queue" "send_user_invites" {
  name = "${local.resource_name_prefix}-sqs-send-user-invites"
}

resource "aws_sfn_state_machine" "send_user_invites" {
  name     = "${local.resource_name_prefix}-sfn-send-user-invites"
  role_arn = aws_iam_role.sfn_send_user_invites.arn

  definition = templatefile("${path.module}/send_user_invites.sfn.json", {
    dyanamodb_table_creators_name = data.aws_dynamodb_table.creators.name,
    lambda_get_user_subs_arn      = data.aws_lambda_function.get_user_subs.arn,
    lambda_send_user_invites_arn     = aws_lambda_function.send_user_invites.arn,
  })

  ### Expected input
  # {
  #   "user_id": "18121313",
  #   "message_id": "460",       (Optional)
  #   "twitch_id": "101319792",
  #   "access_token": "fhasfjakdhflkjdbrhj3r1" (Optional) 
  # }
}

resource "aws_iam_role" "sfn_send_user_invites" {
  name               = "${local.resource_name_prefix}-sfn-send-user-invites-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role_policy.json
}

data "aws_iam_policy_document" "sfn_send_user_invites" {
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
      data.aws_lambda_function.get_user_subs.arn,
      aws_lambda_function.send_user_invites.arn
    ]
    effect = "Allow"
  }
}

resource "aws_iam_role_policy" "sfn_send_user_invites" {
  name   = "${local.resource_name_prefix}-sfn-send-user-invites-role-policy"
  role   = aws_iam_role.sfn_send_user_invites.id
  policy = data.aws_iam_policy_document.sfn_send_user_invites.json
}

###
### Lambda
###

resource "terraform_data" "builder_lambda_send_user_invites" {
  provisioner "local-exec" {
    working_dir = "${path.module}/lambda_send_user_invites/"
    command     = "npm install && npm run build"
  }

  triggers_replace = {
    index    = filebase64sha256("${path.module}/lambda_send_user_invites/index.ts"),
    package  = filebase64sha256("${path.module}/lambda_send_user_invites/package.json"),
    lock     = filebase64sha256("${path.module}/lambda_send_user_invites/package-lock.json"),
    tscongig = filebase64sha256("${path.module}/lambda_send_user_invites/tsconfig.json"),
  }
}

data "archive_file" "archiver_lambda_send_user_invites" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_send_user_invites/dist/"
  output_path = "${path.module}/lambda_send_user_invites/dist/dist.zip"
  excludes    = ["dist.zip"]

  depends_on = [
    terraform_data.builder_lambda_send_user_invites
  ]
}

resource "aws_lambda_function" "send_user_invites" {
  function_name = "${local.resource_name_prefix}-lambda-send-user-invites"

  handler = "index.handler"
  runtime = "nodejs20.x"
  publish = true
  role    = aws_iam_role.lambda_send_user_invites.arn

  filename         = data.archive_file.archiver_lambda_send_user_invites.output_path
  source_code_hash = data.archive_file.archiver_lambda_send_user_invites.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TELEGRAM_BOT_TOKEN = local.telegram_bot_token
      DYNAMODB_TABLE_CREATORS = data.aws_dynamodb_table.creators.name
    }
  }

  depends_on = [
    terraform_data.builder_lambda_send_user_invites,
    data.archive_file.archiver_lambda_send_user_invites
  ]
}

resource "aws_iam_role" "lambda_send_user_invites" {
  name               = "${local.resource_name_prefix}-lambda-send-user-invites-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_send_user_invites" {
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
    actions   = ["dynamodb:Query"]
    resources = ["${data.aws_dynamodb_table.creators.arn}/index/twitch_id_index"]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "lambda_send_user_invites" {
  name   = "${local.resource_name_prefix}-lambda-send-user-invites-role-policy"
  role   = aws_iam_role.lambda_send_user_invites.id
  policy = data.aws_iam_policy_document.lambda_send_user_invites.json
}

###
### Pipes
###

resource "aws_pipes_pipe" "send_user_invites_pipe" {
  name     = "${local.resource_name_prefix}-pipe-send-user-invites"
  role_arn = aws_iam_role.eventbridge_pipe_send_user_invites.arn

  source = aws_sqs_queue.send_user_invites.arn
  source_parameters {
    sqs_queue_parameters {
      batch_size                         = 10
      maximum_batching_window_in_seconds = 0
    }
  }

  target = aws_sfn_state_machine.send_user_invites.arn
  target_parameters {
    step_function_state_machine_parameters {
      invocation_type = "FIRE_AND_FORGET"
    }
  }
}

data "aws_iam_policy_document" "pipes_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pipes.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge_pipe_send_user_invites" {
  name               = "${local.resource_name_prefix}-eventbridge-pipe-send-user-invites-role"
  assume_role_policy = data.aws_iam_policy_document.pipes_assume_role_policy.json
}

data "aws_iam_policy_document" "eventbridge_pipe_send_user_invites" {
  statement {
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.send_user_invites.arn]
    effect    = "Allow"
  }

  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [aws_sqs_queue.send_user_invites.arn]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "eventbridge_pipe_send_user_invites" {
  name   = "${local.resource_name_prefix}-eventbridge-pipe-send-user-invites-role-policy"
  role   = aws_iam_role.eventbridge_pipe_send_user_invites.id
  policy = data.aws_iam_policy_document.eventbridge_pipe_send_user_invites.json
}