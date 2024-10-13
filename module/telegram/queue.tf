resource "aws_sqs_queue" "update_user" {
  name = "${local.resource_name_prefix}-sqs-update-user"
}