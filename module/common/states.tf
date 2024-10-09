resource "aws_dynamodb_table" "states" {
  name         = "${local.resource_name_prefix}-dynamodb-table-auth-states"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "state"

  attribute {
    name = "state"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  deletion_protection_enabled = false # TODO: to change in the future
}

output "dynamodb_table_auth_states" {
  value = aws_dynamodb_table.states.name
}
