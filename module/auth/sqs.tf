resource "aws_sqs_queue" "twitch_callback" {
  name = "${local.resource_name_prefix}-sqs-twitch-callback"
}

resource "aws_lambda_event_source_mapping" "twitch_callback" {
  event_source_arn = aws_sqs_queue.twitch_callback.arn
  function_name    = aws_lambda_function.twitch_callback.arn
  enabled          = true
}
