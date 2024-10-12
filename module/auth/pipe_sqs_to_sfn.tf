resource "aws_pipes_pipe" "twitch_callback_pipe" {
  name        = "${local.resource_name_prefix}-pipe-twitch-callback"
  role_arn    = aws_iam_role.eventbridge_pipe_twitch_callback.arn
  
  source     =  aws_sqs_queue.twitch_callback.arn
  source_parameters {
    sqs_queue_parameters {
      batch_size                         = 1
      maximum_batching_window_in_seconds = 1
    }
  }

  target = aws_sfn_state_machine.twitch_callback.arn
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

resource "aws_iam_role" "eventbridge_pipe_twitch_callback" {
  name = "${local.resource_name_prefix}-eventbridge-pipe-twitch-callback-role"
  assume_role_policy = data.aws_iam_policy_document.pipes_assume_role_policy.json
}

data "aws_iam_policy_document" "eventbridge_pipe_twitch_callback" {
  statement {
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.twitch_callback.arn]
    effect    = "Allow"
  }

  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [aws_sqs_queue.twitch_callback.arn]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "eventbridge_pipe_twitch_callback" {
  name   = "${local.resource_name_prefix}-eventbridge-pipe-twitch-callback-role-policy"
  role   = aws_iam_role.eventbridge_pipe_twitch_callback.id
  policy = data.aws_iam_policy_document.eventbridge_pipe_twitch_callback.json
}
