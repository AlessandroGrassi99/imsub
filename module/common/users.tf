resource "aws_dynamodb_table" "users" {
  name                        = "${local.resource_name_prefix}-dynamodb-table-users"
  billing_mode                = "PAY_PER_REQUEST"
  deletion_protection_enabled = true
  hash_key                    = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }


  attribute {
    name = "twitch_id"
    type = "S"
  }

  global_secondary_index {
    name            = "twitch_id-index"
    hash_key        = "twitch_id"
    projection_type = "ALL"
  }

  # Necessary for EventBridge
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
}

output "dynamodb_table_users" {
  value = aws_dynamodb_table.users.name
}
