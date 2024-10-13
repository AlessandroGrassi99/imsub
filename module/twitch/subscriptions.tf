resource "aws_dynamodb_table" "subscriptions_webhook" {
  name         = "${local.resource_name_prefix}-subscriptions-webhook"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "user_id"
  range_key = "broadcaster_id"

  attribute {
    name = "broadcaster_id"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  global_secondary_index {
    name            = "broadcaster_id_index"
    hash_key        = "broadcaster_id"
    projection_type = "ALL"
  }
}
