resource "aws_sqs_queue" "twitch_callback" {
  name = "${local.resource_name_prefix}-sqs-twitch-callback"
}
