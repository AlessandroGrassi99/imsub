resource "aws_dynamodb_table" "creators" {
  name                        = "${local.resource_name_prefix}-dynamodb-table-creators"
  billing_mode                = "PAY_PER_REQUEST"
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
    name            = "twitch_id_index"
    hash_key        = "twitch_id"
    projection_type = "ALL"
  }

  deletion_protection_enabled = true

  # Necessary for EventBridge
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
}

output "dynamodb_table_creators" {
  value = aws_dynamodb_table.creators.name
}
